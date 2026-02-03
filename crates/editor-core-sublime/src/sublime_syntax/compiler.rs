use crate::sublime_syntax::definition::{
    CaptureSpec, ClearScopes, ContextReference, MatchPattern, MetaPattern, PopAction,
    RawContextPattern, SyntaxDefinition,
};
use crate::sublime_syntax::error::SublimeSyntaxError;
use onig::Regex;
use regex::Regex as RustRegex;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

#[derive(Debug, Clone)]
/// A compiled `.sublime-syntax` definition.
///
/// This is the runtime representation consumed by the highlighter.
pub struct SublimeSyntax {
    /// Optional human-readable name.
    pub name: Option<String>,
    /// Root scope (e.g. `source.rust`).
    pub scope: String,
    /// Syntax format version.
    pub version: u32,
    /// Whether this syntax is hidden from UI pickers.
    pub hidden: bool,
    /// Visible file extensions associated with this syntax.
    pub file_extensions: Vec<String>,
    /// Hidden file extensions associated with this syntax.
    pub hidden_file_extensions: Vec<String>,
    /// Optional `first_line_match` regex source.
    pub first_line_match: Option<String>,
    /// Whether a `prototype` context exists.
    pub prototype_exists: bool,
    /// Compiled contexts keyed by context name.
    pub contexts: HashMap<String, CompiledContext>,
}

#[derive(Debug, Clone)]
/// A compiled Sublime context (meta + pattern list).
pub struct CompiledContext {
    /// Meta scope(s) applied while this context is active.
    pub meta_scope: Vec<String>,
    /// Meta content scope(s) applied to content matched within this context.
    pub meta_content_scope: Vec<String>,
    /// Whether to include the syntax's `prototype` patterns in this context.
    pub include_prototype: bool,
    /// Scope-clearing directive applied when entering this context.
    pub clear_scopes: Option<ClearScopes>,
    /// The patterns that make up this context.
    pub patterns: Vec<CompiledPattern>,

    // Only relevant when this context was created via inheritance merge.
    /// Whether this context prepends patterns when inheriting.
    pub meta_prepend: bool,
    /// Whether this context appends patterns when inheriting.
    pub meta_append: bool,
}

#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone)]
/// A compiled pattern inside a context.
pub enum CompiledPattern {
    /// A regex match pattern.
    Match(CompiledMatchPattern),
    /// An include pattern (context/syntax reference).
    Include(CompiledIncludePattern),
}

#[derive(Debug, Clone)]
/// A compiled `include:` pattern.
pub struct CompiledIncludePattern {
    /// Scope of the syntax that produced this pattern.
    pub origin_scope: String,
    /// The include reference string (e.g. `#main`, `scope:...`, `Packages/...`).
    pub include: String,
    /// Whether to apply the including syntax's prototype.
    pub apply_prototype: bool,
}

#[derive(Debug, Clone)]
/// A compiled `match:` regex pattern.
pub struct CompiledMatchPattern {
    /// Scope of the syntax that produced this pattern.
    pub origin_scope: String,
    /// Original regex source string (after variable substitution).
    pub regex_source: String,
    /// Compiled Oniguruma regex.
    pub regex: Arc<Regex>,

    /// Scopes applied to the matched region.
    pub scope: Vec<String>,
    /// Per-capture scopes keyed by capture group index.
    pub captures: HashMap<u32, Vec<String>>,

    /// Action taken when this pattern matches.
    pub action: MatchAction,
}

#[derive(Debug, Clone)]
/// Action to apply after a match is found.
pub enum MatchAction {
    /// No stack action.
    None,
    /// Pop one or more contexts from the stack.
    Pop {
        /// Number of contexts to pop.
        count: usize,
    },
    /// Push one or more contexts onto the stack.
    Push {
        /// Pop this many contexts before pushing.
        pop_before: usize,
        /// Context(s) to push.
        push: ContextPush,
        /// Prototype patterns applied while the pushed contexts are active.
        with_prototype: Vec<CompiledPattern>,
    },
    /// Replace (set) the current context stack with new contexts.
    Set {
        /// Pop this many contexts before setting.
        pop_before: usize,
        /// Context(s) to set (push after popping).
        set: ContextPush,
        /// Prototype patterns applied while the new contexts are active.
        with_prototype: Vec<CompiledPattern>,
    },
    /// Temporarily embed another syntax until an escape pattern is matched.
    Embed {
        /// Pop this many contexts before entering the embed.
        pop_before: usize,
        /// The embedded syntax reference.
        embed: String,
        /// Scope(s) applied to the embedded content.
        embed_scope: Vec<String>,
        /// Original escape regex source string.
        escape_source: String,
        /// Compiled escape regex.
        escape: Arc<Regex>,
        /// Per-capture scopes for the escape match.
        escape_captures: HashMap<u32, Vec<String>>,
        /// Prototype patterns applied while embedded.
        with_prototype: Vec<CompiledPattern>,
    },
}

#[derive(Debug, Clone)]
/// A specification of contexts to push/set.
pub enum ContextPush {
    /// A single context.
    One(ContextSpec),
    /// Multiple contexts (pushed in order).
    Many(Vec<ContextSpec>),
}

#[derive(Debug, Clone)]
/// A context reference used in stack operations.
pub enum ContextSpec {
    /// Push a named context.
    Named {
        /// Scope of the syntax that produced this reference.
        origin_scope: String,
        /// Name of the context within the syntax.
        name: String,
    },
    /// Push an inline (anonymous) context.
    Inline {
        /// Scope of the syntax that produced this context.
        origin_scope: String,
        /// Compiled context content.
        context: CompiledContext,
    },
}

impl SublimeSyntax {
    /// Compile a parsed [`SyntaxDefinition`] into a [`SublimeSyntax`].
    pub fn compile(mut definition: SyntaxDefinition) -> Result<Self, SublimeSyntaxError> {
        if !definition.contexts.contains_key("main") {
            return Err(SublimeSyntaxError::MissingField("contexts.main"));
        }

        let realized_vars = realize_variables(&definition.variables)?;
        definition.variables = realized_vars.clone();

        if let Some(first) = &definition.first_line_match {
            definition.first_line_match = Some(substitute_variables(first, &realized_vars)?);
        }

        let prototype_exists = definition.contexts.contains_key("prototype");

        let mut contexts = HashMap::new();
        for (name, patterns) in &definition.contexts {
            let compiled = compile_context(patterns, &realized_vars, &definition.scope)?;
            contexts.insert(name.clone(), compiled);
        }

        Ok(Self {
            name: definition.name,
            scope: definition.scope,
            version: definition.version,
            hidden: definition.hidden,
            file_extensions: definition.file_extensions,
            hidden_file_extensions: definition.hidden_file_extensions,
            first_line_match: definition.first_line_match,
            prototype_exists,
            contexts,
        })
    }
}

fn compile_context(
    patterns: &[RawContextPattern],
    variables: &HashMap<String, String>,
    origin_scope: &str,
) -> Result<CompiledContext, SublimeSyntaxError> {
    let mut meta = ContextMetaCollector::default();
    let mut compiled_patterns = Vec::new();

    let mut in_meta = true;
    for pattern in patterns {
        match pattern {
            RawContextPattern::Meta(m) if in_meta => {
                meta.apply(m);
            }
            RawContextPattern::Meta(_) => {
                // Sublime requires meta patterns to appear first. We ignore any that show up
                // later to avoid silently applying partial/incorrect state.
                return Err(SublimeSyntaxError::Unsupported(
                    "meta patterns must be listed first in a context",
                ));
            }
            RawContextPattern::Match(m) => {
                in_meta = false;
                compiled_patterns.push(CompiledPattern::Match(compile_match(
                    m,
                    variables,
                    origin_scope,
                )?));
            }
            RawContextPattern::Include(i) => {
                in_meta = false;
                compiled_patterns.push(CompiledPattern::Include(CompiledIncludePattern {
                    origin_scope: origin_scope.to_string(),
                    include: i.include.clone(),
                    apply_prototype: i.apply_prototype.unwrap_or(false),
                }));
            }
        }
    }

    Ok(CompiledContext {
        meta_scope: split_scopes(meta.meta_scope.as_deref()),
        meta_content_scope: split_scopes(meta.meta_content_scope.as_deref()),
        include_prototype: meta.meta_include_prototype.unwrap_or(true),
        clear_scopes: meta.clear_scopes,
        patterns: compiled_patterns,
        meta_prepend: meta.meta_prepend.unwrap_or(false),
        meta_append: meta.meta_append.unwrap_or(false),
    })
}

#[derive(Debug, Default)]
struct ContextMetaCollector {
    meta_scope: Option<String>,
    meta_content_scope: Option<String>,
    meta_include_prototype: Option<bool>,
    clear_scopes: Option<ClearScopes>,
    meta_prepend: Option<bool>,
    meta_append: Option<bool>,
}

impl ContextMetaCollector {
    fn apply(&mut self, meta: &MetaPattern) {
        if let Some(v) = &meta.meta_scope {
            self.meta_scope = Some(v.clone());
        }
        if let Some(v) = &meta.meta_content_scope {
            self.meta_content_scope = Some(v.clone());
        }
        if let Some(v) = meta.meta_include_prototype {
            self.meta_include_prototype = Some(v);
        }
        if let Some(v) = &meta.clear_scopes {
            self.clear_scopes = Some(v.clone());
        }
        if let Some(v) = meta.meta_prepend {
            self.meta_prepend = Some(v);
        }
        if let Some(v) = meta.meta_append {
            self.meta_append = Some(v);
        }
    }
}

fn compile_match(
    pattern: &MatchPattern,
    variables: &HashMap<String, String>,
    origin_scope: &str,
) -> Result<CompiledMatchPattern, SublimeSyntaxError> {
    if pattern.branch.is_some() || pattern.fail.is_some() || pattern.branch_point.is_some() {
        return Err(SublimeSyntaxError::Unsupported("branch/fail"));
    }

    let regex_source = substitute_variables(&pattern.regex, variables)?;
    let regex = Regex::new(&regex_source).map_err(|e| SublimeSyntaxError::RegexCompile {
        pattern: regex_source.clone(),
        message: e.to_string(),
    })?;

    let mut captures = HashMap::new();
    for (idx, spec) in &pattern.captures {
        captures.insert(*idx, flatten_capture_spec(spec));
    }

    let mut escape_captures = HashMap::new();
    for (idx, spec) in &pattern.escape_captures {
        escape_captures.insert(*idx, flatten_capture_spec(spec));
    }

    let with_prototype = pattern
        .with_prototype
        .as_deref()
        .unwrap_or_default()
        .iter()
        .map(|p| compile_inline_pattern(p, variables, origin_scope))
        .collect::<Result<Vec<_>, _>>()?;

    let pop_before = match &pattern.pop {
        None => 0,
        Some(PopAction::Bool(true)) => 1,
        Some(PopAction::Bool(false)) => 0,
        Some(PopAction::Count(n)) => *n,
    };

    let action = if let Some(embed) = &pattern.embed {
        let Some(escape) = &pattern.escape else {
            return Err(SublimeSyntaxError::MissingField(
                "escape (required by embed)",
            ));
        };

        let escape_source = substitute_variables(escape, variables)?;
        let escape_regex =
            Regex::new(&escape_source).map_err(|e| SublimeSyntaxError::RegexCompile {
                pattern: escape_source.clone(),
                message: e.to_string(),
            })?;

        MatchAction::Embed {
            pop_before,
            embed: embed.clone(),
            embed_scope: split_scopes(pattern.embed_scope.as_deref()),
            escape_source,
            escape: Arc::new(escape_regex),
            escape_captures,
            with_prototype,
        }
    } else if let Some(set) = &pattern.set {
        MatchAction::Set {
            pop_before,
            set: compile_context_push(set, variables, origin_scope)?,
            with_prototype,
        }
    } else if let Some(push) = &pattern.push {
        MatchAction::Push {
            pop_before,
            push: compile_context_push(push, variables, origin_scope)?,
            with_prototype,
        }
    } else if pop_before > 0 {
        MatchAction::Pop { count: pop_before }
    } else {
        if !with_prototype.is_empty() {
            return Err(SublimeSyntaxError::Unsupported(
                "with_prototype without push/set/embed",
            ));
        }
        MatchAction::None
    };

    Ok(CompiledMatchPattern {
        origin_scope: origin_scope.to_string(),
        regex_source,
        regex: Arc::new(regex),
        scope: split_scopes(pattern.scope.as_deref()),
        captures,
        action,
    })
}

fn compile_context_push(
    ctx: &ContextReference,
    variables: &HashMap<String, String>,
    origin_scope: &str,
) -> Result<ContextPush, SublimeSyntaxError> {
    match ctx {
        ContextReference::Name(name) => Ok(ContextPush::One(ContextSpec::Named {
            origin_scope: origin_scope.to_string(),
            name: name.clone(),
        })),
        ContextReference::Names(names) => Ok(ContextPush::Many(
            names
                .iter()
                .map(|n| ContextSpec::Named {
                    origin_scope: origin_scope.to_string(),
                    name: n.clone(),
                })
                .collect(),
        )),
        ContextReference::Inline(patterns) => {
            let inline = compile_context(patterns, variables, origin_scope)?;
            Ok(ContextPush::One(ContextSpec::Inline {
                origin_scope: origin_scope.to_string(),
                context: inline,
            }))
        }
    }
}

fn compile_inline_pattern(
    pattern: &RawContextPattern,
    variables: &HashMap<String, String>,
    origin_scope: &str,
) -> Result<CompiledPattern, SublimeSyntaxError> {
    match pattern {
        RawContextPattern::Meta(_) => Err(SublimeSyntaxError::Unsupported(
            "meta patterns in with_prototype/inline contexts",
        )),
        RawContextPattern::Match(m) => Ok(CompiledPattern::Match(compile_match(
            m,
            variables,
            origin_scope,
        )?)),
        RawContextPattern::Include(i) => Ok(CompiledPattern::Include(CompiledIncludePattern {
            origin_scope: origin_scope.to_string(),
            include: i.include.clone(),
            apply_prototype: i.apply_prototype.unwrap_or(false),
        })),
    }
}

fn flatten_capture_spec(spec: &CaptureSpec) -> Vec<String> {
    match spec {
        CaptureSpec::Scope(s) => split_scopes(Some(s.as_str())),
        CaptureSpec::Complex { scope, captures: _ } => split_scopes(Some(scope.as_str())),
    }
}

fn split_scopes(scopes: Option<&str>) -> Vec<String> {
    let Some(scopes) = scopes else {
        return Vec::new();
    };
    scopes
        .split_whitespace()
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect()
}

fn realize_variables(
    vars: &HashMap<String, String>,
) -> Result<HashMap<String, String>, SublimeSyntaxError> {
    let mut realized = HashMap::new();
    let mut visiting = HashSet::<String>::new();

    for key in vars.keys() {
        let _ = realize_one_variable(key, vars, &mut realized, &mut visiting)?;
    }

    Ok(realized)
}

fn realize_one_variable(
    key: &str,
    vars: &HashMap<String, String>,
    realized: &mut HashMap<String, String>,
    visiting: &mut HashSet<String>,
) -> Result<String, SublimeSyntaxError> {
    if let Some(val) = realized.get(key) {
        return Ok(val.clone());
    }
    if !visiting.insert(key.to_string()) {
        return Err(SublimeSyntaxError::CircularVariableReference(
            key.to_string(),
        ));
    }

    let raw = vars
        .get(key)
        .ok_or_else(|| SublimeSyntaxError::UnknownVariable(key.to_string()))?;

    let mut out = String::new();
    let mut last = 0usize;
    for (m_start, m_end, name) in variable_refs(raw) {
        out.push_str(&raw[last..m_start]);
        let expanded = realize_one_variable(&name, vars, realized, visiting)?;
        out.push_str(&expanded);
        last = m_end;
    }
    out.push_str(&raw[last..]);

    visiting.remove(key);
    realized.insert(key.to_string(), out.clone());
    Ok(out)
}

fn substitute_variables(
    text: &str,
    vars: &HashMap<String, String>,
) -> Result<String, SublimeSyntaxError> {
    let mut out = String::new();
    let mut last = 0usize;
    for (m_start, m_end, name) in variable_refs(text) {
        out.push_str(&text[last..m_start]);
        let value = vars
            .get(&name)
            .ok_or_else(|| SublimeSyntaxError::UnknownVariable(name.clone()))?;
        out.push_str(value);
        last = m_end;
    }
    out.push_str(&text[last..]);
    Ok(out)
}

fn variable_refs(text: &str) -> Vec<(usize, usize, String)> {
    // Per docs: only {{[A-Za-z0-9_]+}} are treated as variables.
    // Everything else (including literal '{{') should remain unchanged.
    //
    // Using a small regex keeps this logic simple and deterministic.
    let re = RustRegex::new(r"\{\{([A-Za-z0-9_]+)\}\}").expect("valid variable regex");
    re.captures_iter(text)
        .filter_map(|cap| {
            let m = cap.get(0)?;
            let name = cap.get(1)?.as_str().to_string();
            Some((m.start(), m.end(), name))
        })
        .collect()
}
