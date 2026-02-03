use crate::sublime_syntax::compiler::{
    CompiledContext, CompiledIncludePattern, CompiledMatchPattern, CompiledPattern, ContextPush,
    ContextSpec, MatchAction, SublimeSyntax,
};
use crate::sublime_syntax::definition::ClearScopes;
use crate::sublime_syntax::error::SublimeSyntaxError;
use crate::sublime_syntax::scope::SublimeScopeMapper;
use crate::sublime_syntax::set::SublimeSyntaxSet;
use editor_core::LineIndex;
use editor_core::intervals::{FoldRegion, Interval, StyleId};
use onig::{Region, SearchOptions};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

#[derive(Debug, Default)]
/// Highlighting output produced by [`highlight_document`].
pub struct SublimeHighlightResult {
    /// Style intervals in character offsets.
    pub intervals: Vec<Interval>,
    /// Fold regions inferred from multi-line contexts.
    pub fold_regions: Vec<FoldRegion>,
}

/// Highlights a document and derives fold regions from multi-line contexts.
///
/// - Intervals are in **char offsets**, consistent with `LineIndex` and the rest of editor-core.
/// - The returned intervals are non-overlapping within this result (best-effort).
pub fn highlight_document(
    syntax: Arc<SublimeSyntax>,
    line_index: &LineIndex,
    syntax_set: Option<&mut SublimeSyntaxSet>,
    scope_mapper: &mut SublimeScopeMapper,
) -> Result<SublimeHighlightResult, SublimeSyntaxError> {
    let mut syntax_set = syntax_set;
    let mut engine = Highlighter::new(syntax, scope_mapper);
    engine.highlight(line_index, &mut syntax_set)
}

struct Highlighter<'a> {
    root_syntax: Arc<SublimeSyntax>,
    scope_mapper: &'a mut SublimeScopeMapper,
    pattern_cache: PatternCache,
    context_stack: Vec<ContextFrame>,
    fold_regions: Vec<FoldRegion>,
}

impl<'a> Highlighter<'a> {
    fn new(syntax: Arc<SublimeSyntax>, scope_mapper: &'a mut SublimeScopeMapper) -> Self {
        Self {
            root_syntax: syntax,
            scope_mapper,
            pattern_cache: PatternCache::default(),
            context_stack: Vec::new(),
            fold_regions: Vec::new(),
        }
    }

    fn highlight(
        &mut self,
        line_index: &LineIndex,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<SublimeHighlightResult, SublimeSyntaxError> {
        if !self.root_syntax.contexts.contains_key("main") {
            return Err(SublimeSyntaxError::MissingField("contexts.main"));
        }

        self.context_stack.push(ContextFrame::named(
            self.root_syntax.clone(),
            "main".to_string(),
            0,
        ));

        let base_scope = self.root_syntax.scope.clone();
        let mut intervals = Vec::<Interval>::new();

        let line_count = line_index.line_count();
        for line in 0..line_count {
            let line_text = line_index.get_line_text(line).unwrap_or_default();
            let line_start_offset = line_index.position_to_char_offset(line, 0);

            let mut pos_byte = 0usize;
            let mut pos_char = 0usize;
            let line_len_bytes = line_text.len();

            // Prevent infinite loops with zero-width matches.
            // Sublime itself has more nuanced behavior; we keep a generous bound.
            let mut iterations = 0usize;
            let max_iterations = (line_len_bytes + 1).saturating_mul(32).max(128);

            while pos_byte <= line_len_bytes {
                iterations += 1;
                if iterations > max_iterations {
                    return Err(SublimeSyntaxError::Unsupported(
                        "highlighting exceeded iteration limit (possible zero-width loop)",
                    ));
                }

                let Some(found) = self.find_next_match(&line_text, pos_byte, syntax_set)? else {
                    let end_char = pos_char + line_text[pos_byte..].chars().count();
                    let style = self.best_style_for_content();
                    self.emit_segment(
                        &mut intervals,
                        line_start_offset + pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );
                    break;
                };

                // Emit content before the match.
                if found.start_byte > pos_byte {
                    let segment_chars = line_text[pos_byte..found.start_byte].chars().count();
                    let end_char = pos_char + segment_chars;
                    let style = self.best_style_for_content();
                    self.emit_segment(
                        &mut intervals,
                        line_start_offset + pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );
                    pos_char = end_char;
                    pos_byte = found.start_byte;
                }

                // Emit match region (may be empty for lookaheads).
                if found.end_byte > found.start_byte {
                    let match_chars = line_text[found.start_byte..found.end_byte].chars().count();
                    let end_char = pos_char + match_chars;

                    let style = self.best_style_for_match(&found.pattern);
                    self.emit_segment(
                        &mut intervals,
                        line_start_offset + pos_char,
                        line_start_offset + end_char,
                        style,
                        base_scope.as_str(),
                    );

                    pos_char = end_char;
                    pos_byte = found.end_byte;
                }

                let stack_len_before = self.context_stack.len();
                self.apply_action(found.pattern.action.clone(), line, syntax_set)?;
                let stack_len_after = self.context_stack.len();

                // If this is a zero-width match and the stack didn't change, we must
                // ensure progress to avoid an infinite loop. At end-of-line we can
                // stop since there is nothing left to consume.
                if found.start_byte == found.end_byte
                    && found.start_byte == pos_byte
                    && stack_len_before == stack_len_after
                {
                    if pos_byte >= line_len_bytes {
                        break;
                    }

                    // Advance by one UTF-8 char boundary.
                    let mut iter = line_text[pos_byte..].char_indices();
                    let _ = iter.next();
                    if let Some((next_rel, _)) = iter.next() {
                        pos_byte += next_rel;
                        pos_char += 1;
                    } else {
                        // Single remaining char.
                        pos_byte = line_len_bytes;
                        pos_char += 1;
                    }
                }
            }
        }

        // Close any remaining contexts at EOF for folding purposes.
        let last_line = line_count.saturating_sub(1);
        while self.context_stack.len() > 1 {
            self.pop_one_context(last_line);
        }

        Ok(SublimeHighlightResult {
            intervals,
            fold_regions: std::mem::take(&mut self.fold_regions),
        })
    }

    fn emit_segment(
        &mut self,
        intervals: &mut Vec<Interval>,
        start: usize,
        end: usize,
        style_id: StyleId,
        base_scope: &str,
    ) {
        if start >= end {
            return;
        }

        // Skip base scope to keep intervals smaller; consumers can treat "no style"
        // as the base.
        if self
            .scope_mapper
            .scope_for_style_id(style_id)
            .is_some_and(|s| s == base_scope)
        {
            return;
        }

        if let Some(last) = intervals.last_mut()
            && last.style_id == style_id
            && last.end == start
        {
            last.end = end;
            return;
        }

        intervals.push(Interval::new(start, end, style_id));
    }

    fn find_next_match(
        &mut self,
        line_text: &str,
        from_byte: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Option<FoundMatch>, SublimeSyntaxError> {
        let Some(top) = self.context_stack.last() else {
            return Ok(None);
        };

        let snapshot = top.snapshot();
        let patterns = self.flatten_patterns_for_snapshot(&snapshot, syntax_set)?;

        let mut best: Option<FoundMatch> = None;
        for pattern in patterns {
            let Some((start, end)) = search_first(&pattern.regex, line_text, from_byte)? else {
                continue;
            };

            match &best {
                None => {
                    best = Some(FoundMatch {
                        start_byte: start,
                        end_byte: end,
                        pattern,
                    });
                }
                Some(existing) => {
                    if start < existing.start_byte {
                        best = Some(FoundMatch {
                            start_byte: start,
                            end_byte: end,
                            pattern,
                        });
                    } else if start == existing.start_byte {
                        // Tie-break by definition order: since we iterate in order,
                        // keep the first one.
                    }
                }
            }
        }

        Ok(best)
    }

    fn flatten_patterns_for_snapshot(
        &mut self,
        frame: &ContextFrameSnapshot,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let ctx = frame.context()?;
        if frame.is_inline {
            return self.flatten_inline_context_patterns(frame, ctx, syntax_set);
        }

        let mut base_patterns = self.pattern_cache.flatten_named_context(
            &frame.syntax,
            &frame.context_name,
            syntax_set.as_deref_mut(),
        )?;

        if frame.injected_patterns.is_empty() {
            return Ok(base_patterns);
        }

        let mut out = Vec::new();
        let mut visiting = HashSet::new();
        for injected in &frame.injected_patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                injected,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut visiting,
            )?;
        }
        out.append(&mut base_patterns);
        Ok(out)
    }

    fn flatten_inline_context_patterns(
        &mut self,
        frame: &ContextFrameSnapshot,
        ctx: &CompiledContext,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let mut out = Vec::new();

        // Injected patterns (from `with_prototype`) come first.
        for injected in &frame.injected_patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                injected,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut HashSet::new(),
            )?;
        }

        // Prototype context if present & enabled.
        if ctx.include_prototype
            && frame.syntax.prototype_exists
            && frame.context_name != "prototype"
        {
            let proto = self.pattern_cache.flatten_named_context(
                &frame.syntax,
                "prototype",
                syntax_set.as_deref_mut(),
            )?;
            out.extend(proto);
        }

        // Then inline context patterns.
        for pattern in &ctx.patterns {
            self.flatten_compiled_pattern(
                &frame.syntax,
                pattern,
                syntax_set.as_deref_mut(),
                &mut out,
                &mut HashSet::new(),
            )?;
        }

        Ok(out)
    }

    fn flatten_compiled_pattern(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        pattern: &CompiledPattern,
        syntax_set: Option<&mut SublimeSyntaxSet>,
        out: &mut Vec<CompiledMatchPattern>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<(), SublimeSyntaxError> {
        match pattern {
            CompiledPattern::Match(m) => {
                out.push(m.clone());
            }
            CompiledPattern::Include(i) => {
                self.flatten_include(syntax, i, syntax_set, out, visiting)?;
            }
        }
        Ok(())
    }

    fn flatten_include(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        include: &CompiledIncludePattern,
        mut syntax_set: Option<&mut SublimeSyntaxSet>,
        out: &mut Vec<CompiledMatchPattern>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<(), SublimeSyntaxError> {
        let target = include.include.as_str();

        // External syntax include: include the referenced syntax's main context.
        if is_external_syntax_reference(target) {
            let Some(set) = syntax_set.as_deref_mut() else {
                return Err(SublimeSyntaxError::Unsupported(
                    "including external syntaxes requires a SublimeSyntaxSet",
                ));
            };
            let other = set.load_by_reference(target)?;
            let other_patterns =
                self.pattern_cache
                    .flatten_named_context(&other, "main", Some(set))?;
            out.extend(other_patterns);
            return Ok(());
        }

        let key = (syntax.scope.clone(), target.to_string());
        if !visiting.insert(key.clone()) {
            return Err(SublimeSyntaxError::Unsupported(
                "include cycle detected while expanding contexts",
            ));
        }

        // Prototype injection for included contexts is handled by flatten_named_context.
        let patterns = self
            .pattern_cache
            .flatten_named_context(syntax, target, syntax_set)?;
        out.extend(patterns);

        visiting.remove(&key);
        Ok(())
    }

    fn best_style_for_content(&mut self) -> StyleId {
        let scopes = compute_scopes(
            &self.context_stack,
            ScopeMode::Content,
            None,
            &self.root_syntax.scope,
        );
        let best = scopes
            .last()
            .map(|s| s.as_str())
            .unwrap_or(&self.root_syntax.scope);
        self.scope_mapper.style_id_for_scope(best)
    }

    fn best_style_for_match(&mut self, pattern: &CompiledMatchPattern) -> StyleId {
        let scopes = compute_scopes(
            &self.context_stack,
            ScopeMode::Match,
            Some(&pattern.scope),
            &self.root_syntax.scope,
        );
        let best = scopes
            .last()
            .map(|s| s.as_str())
            .unwrap_or(&self.root_syntax.scope);
        self.scope_mapper.style_id_for_scope(best)
    }

    fn apply_action(
        &mut self,
        action: MatchAction,
        line: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        match action {
            MatchAction::None => Ok(()),
            MatchAction::Pop { count } => {
                for _ in 0..count {
                    self.pop_one_context(line);
                }
                Ok(())
            }
            MatchAction::Push {
                pop_before,
                push,
                with_prototype,
            } => {
                let mut inherited = self
                    .context_stack
                    .last()
                    .map(|f| f.injected_patterns.clone())
                    .unwrap_or_default();
                inherited.extend(with_prototype);
                for _ in 0..pop_before {
                    self.pop_one_context(line);
                }
                self.push_contexts(push, inherited, line, syntax_set)
            }
            MatchAction::Set {
                pop_before,
                set,
                with_prototype,
            } => {
                let mut inherited = self
                    .context_stack
                    .last()
                    .map(|f| f.injected_patterns.clone())
                    .unwrap_or_default();
                inherited.extend(with_prototype);
                for _ in 0..pop_before {
                    self.pop_one_context(line);
                }
                self.pop_one_context(line);
                self.push_contexts(set, inherited, line, syntax_set)
            }
            MatchAction::Embed { .. } => Err(SublimeSyntaxError::Unsupported("embed")),
        }
    }

    fn push_contexts(
        &mut self,
        push: ContextPush,
        with_prototype: Vec<CompiledPattern>,
        line: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        match push {
            ContextPush::One(spec) => {
                self.push_context_spec(spec, with_prototype, line, syntax_set)
            }
            ContextPush::Many(specs) => {
                for spec in specs {
                    self.push_context_spec(spec, with_prototype.clone(), line, syntax_set)?;
                }
                Ok(())
            }
        }
    }

    fn push_context_spec(
        &mut self,
        spec: ContextSpec,
        injected_patterns: Vec<CompiledPattern>,
        line: usize,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<(), SublimeSyntaxError> {
        match spec {
            ContextSpec::Named { origin_scope, name } => {
                if is_external_syntax_reference(&name) {
                    let Some(set) = syntax_set.as_deref_mut() else {
                        return Err(SublimeSyntaxError::Unsupported(
                            "pushing external syntaxes requires a SublimeSyntaxSet",
                        ));
                    };
                    let syntax = set.load_by_reference(&name)?;
                    self.context_stack.push(ContextFrame::named_with_injected(
                        syntax,
                        "main".to_string(),
                        injected_patterns,
                        line,
                    ));
                    return Ok(());
                }

                let syntax = self.syntax_for_scope(&origin_scope, syntax_set)?;
                self.context_stack.push(ContextFrame::named_with_injected(
                    syntax,
                    name,
                    injected_patterns,
                    line,
                ));
                Ok(())
            }
            ContextSpec::Inline {
                origin_scope,
                context,
            } => {
                let syntax = self.syntax_for_scope(&origin_scope, syntax_set)?;
                self.context_stack.push(ContextFrame::inline_with_injected(
                    syntax,
                    context,
                    injected_patterns,
                    line,
                ));
                Ok(())
            }
        }
    }

    fn syntax_for_scope(
        &mut self,
        scope: &str,
        syntax_set: &mut Option<&mut SublimeSyntaxSet>,
    ) -> Result<Arc<SublimeSyntax>, SublimeSyntaxError> {
        if self.root_syntax.scope == scope {
            return Ok(self.root_syntax.clone());
        }
        let Some(set) = syntax_set.as_deref() else {
            return Err(SublimeSyntaxError::UnknownSyntaxReference(
                scope.to_string(),
            ));
        };
        set.get_by_scope(scope)
            .ok_or_else(|| SublimeSyntaxError::UnknownSyntaxReference(scope.to_string()))
    }

    fn pop_one_context(&mut self, line: usize) {
        if self.context_stack.len() <= 1 {
            return;
        }

        let frame = self.context_stack.pop().expect("len checked");
        let ctx = match frame.context() {
            Ok(c) => c,
            Err(_) => return,
        };

        if !ctx.meta_scope.is_empty() && line > frame.entered_at_line {
            self.fold_regions
                .push(FoldRegion::new(frame.entered_at_line, line));
        }
    }
}

#[derive(Debug)]
struct ContextFrame {
    syntax: Arc<SublimeSyntax>,
    context_name: String,
    is_inline: bool,
    inline_context: Option<CompiledContext>,
    injected_patterns: Vec<CompiledPattern>,
    entered_at_line: usize,
}

impl ContextFrame {
    fn named(syntax: Arc<SublimeSyntax>, name: String, entered_at_line: usize) -> Self {
        Self {
            syntax,
            context_name: name,
            is_inline: false,
            inline_context: None,
            injected_patterns: Vec::new(),
            entered_at_line,
        }
    }

    fn named_with_injected(
        syntax: Arc<SublimeSyntax>,
        name: String,
        injected_patterns: Vec<CompiledPattern>,
        entered_at_line: usize,
    ) -> Self {
        Self {
            syntax,
            context_name: name,
            is_inline: false,
            inline_context: None,
            injected_patterns,
            entered_at_line,
        }
    }

    fn inline_with_injected(
        syntax: Arc<SublimeSyntax>,
        context: CompiledContext,
        injected_patterns: Vec<CompiledPattern>,
        entered_at_line: usize,
    ) -> Self {
        Self {
            syntax,
            context_name: "<inline>".to_string(),
            is_inline: true,
            inline_context: Some(context),
            injected_patterns,
            entered_at_line,
        }
    }

    fn context(&self) -> Result<&CompiledContext, SublimeSyntaxError> {
        if self.is_inline {
            return self
                .inline_context
                .as_ref()
                .ok_or(SublimeSyntaxError::MissingField("inline context"));
        }
        self.syntax
            .contexts
            .get(&self.context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(self.context_name.clone()))
    }

    fn snapshot(&self) -> ContextFrameSnapshot {
        ContextFrameSnapshot {
            syntax: self.syntax.clone(),
            context_name: self.context_name.clone(),
            is_inline: self.is_inline,
            inline_context: self.inline_context.clone(),
            injected_patterns: self.injected_patterns.clone(),
        }
    }
}

#[derive(Debug, Clone)]
struct ContextFrameSnapshot {
    syntax: Arc<SublimeSyntax>,
    context_name: String,
    is_inline: bool,
    inline_context: Option<CompiledContext>,
    injected_patterns: Vec<CompiledPattern>,
}

impl ContextFrameSnapshot {
    fn context(&self) -> Result<&CompiledContext, SublimeSyntaxError> {
        if self.is_inline {
            return self
                .inline_context
                .as_ref()
                .ok_or(SublimeSyntaxError::MissingField("inline context"));
        }
        self.syntax
            .contexts
            .get(&self.context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(self.context_name.clone()))
    }
}

#[derive(Debug)]
struct FoundMatch {
    start_byte: usize,
    end_byte: usize,
    pattern: CompiledMatchPattern,
}

#[derive(Debug, Default)]
struct PatternCache {
    // Keyed by (syntax_scope, context_name)
    flat: HashMap<(String, String), Vec<CompiledMatchPattern>>,
}

impl PatternCache {
    fn flatten_named_context(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        context_name: &str,
        syntax_set: Option<&mut SublimeSyntaxSet>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let key = (syntax.scope.clone(), context_name.to_string());
        if let Some(cached) = self.flat.get(&key) {
            return Ok(cached.clone());
        }

        let mut visiting = HashSet::<(String, String)>::new();
        let patterns =
            self.flatten_named_context_inner(syntax, context_name, syntax_set, &mut visiting)?;
        self.flat.insert(key, patterns.clone());
        Ok(patterns)
    }

    fn flatten_named_context_inner(
        &mut self,
        syntax: &Arc<SublimeSyntax>,
        context_name: &str,
        mut syntax_set: Option<&mut SublimeSyntaxSet>,
        visiting: &mut HashSet<(String, String)>,
    ) -> Result<Vec<CompiledMatchPattern>, SublimeSyntaxError> {
        let key = (syntax.scope.clone(), context_name.to_string());
        if !visiting.insert(key.clone()) {
            return Err(SublimeSyntaxError::Unsupported(
                "include cycle detected while expanding contexts",
            ));
        }

        let ctx = syntax
            .contexts
            .get(context_name)
            .ok_or_else(|| SublimeSyntaxError::UnknownContext(context_name.to_string()))?;

        let mut out = Vec::new();

        if ctx.include_prototype && syntax.prototype_exists && context_name != "prototype" {
            let proto = self.flatten_named_context_inner(
                syntax,
                "prototype",
                syntax_set.as_deref_mut(),
                visiting,
            )?;
            out.extend(proto);
        }

        for pattern in &ctx.patterns {
            match pattern {
                CompiledPattern::Match(m) => out.push(m.clone()),
                CompiledPattern::Include(i) => {
                    let target = i.include.as_str();
                    if is_external_syntax_reference(target) {
                        let Some(set) = syntax_set.as_deref_mut() else {
                            return Err(SublimeSyntaxError::Unsupported(
                                "including external syntaxes requires a SublimeSyntaxSet",
                            ));
                        };
                        let other = set.load_by_reference(target)?;
                        let other_patterns =
                            self.flatten_named_context(&other, "main", Some(set))?;
                        out.extend(other_patterns);
                    } else {
                        let included = self.flatten_named_context_inner(
                            syntax,
                            target,
                            syntax_set.as_deref_mut(),
                            visiting,
                        )?;
                        out.extend(included);
                    }
                }
            }
        }

        visiting.remove(&key);
        Ok(out)
    }
}

fn is_external_syntax_reference(name: &str) -> bool {
    name.starts_with("scope:")
        || name.starts_with("Packages/")
        || name.ends_with(".sublime-syntax")
        || name.contains("/Packages/")
}

fn search_first(
    regex: &Arc<onig::Regex>,
    text: &str,
    from: usize,
) -> Result<Option<(usize, usize)>, SublimeSyntaxError> {
    let mut region = Region::new();
    let len = text.len();
    let Some(_) = regex.search_with_options(
        text,
        from,
        len,
        SearchOptions::SEARCH_OPTION_NONE,
        Some(&mut region),
    ) else {
        return Ok(None);
    };

    Ok(region.pos(0))
}

#[derive(Debug, Clone, Copy)]
enum ScopeMode {
    Content,
    Match,
}

fn compute_scopes(
    frames: &[ContextFrame],
    mode: ScopeMode,
    match_scope: Option<&Vec<String>>,
    base_scope: &str,
) -> Vec<String> {
    let mut stack: Vec<String> = Vec::new();
    stack.push(base_scope.to_string());

    let top_idx = frames.len().saturating_sub(1);
    for (idx, frame) in frames.iter().enumerate() {
        let Ok(ctx) = frame.context() else {
            continue;
        };

        apply_clear_scopes(&mut stack, ctx);
        stack.extend(ctx.meta_scope.iter().cloned());

        let include_content_scopes = match mode {
            ScopeMode::Content => true,
            ScopeMode::Match => idx != top_idx,
        };
        if include_content_scopes {
            stack.extend(ctx.meta_content_scope.iter().cloned());
        }
    }

    if let (ScopeMode::Match, Some(scope)) = (mode, match_scope) {
        stack.extend(scope.iter().cloned());
    }

    stack
}

fn apply_clear_scopes(stack: &mut Vec<String>, ctx: &CompiledContext) {
    let Some(clear) = &ctx.clear_scopes else {
        return;
    };

    match clear {
        ClearScopes::Count(n) => {
            let n = (*n).min(stack.len());
            stack.truncate(stack.len().saturating_sub(n));
        }
        ClearScopes::All(true) => {
            stack.clear();
        }
        ClearScopes::All(false) => {}
    }
}
