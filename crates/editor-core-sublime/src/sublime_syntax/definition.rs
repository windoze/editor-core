use serde::Deserialize;
use serde_yaml::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
/// `extends:` field in a `.sublime-syntax` definition.
pub enum Extends {
    /// A single parent syntax reference.
    One(String),
    /// Multiple parent syntax references.
    Many(Vec<String>),
}

#[derive(Debug, Clone, Deserialize)]
/// Raw YAML `.sublime-syntax` definition.
pub struct SyntaxDefinition {
    #[serde(default)]
    /// Optional human-readable name.
    pub name: Option<String>,

    #[serde(default)]
    /// File extensions associated with this syntax.
    pub file_extensions: Vec<String>,

    #[serde(default)]
    /// File extensions that should be hidden from UI pickers.
    pub hidden_file_extensions: Vec<String>,

    #[serde(default)]
    /// Optional first-line regex used to detect the syntax.
    pub first_line_match: Option<String>,

    /// Root scope (e.g. `source.rust`).
    pub scope: String,

    #[serde(default = "default_version")]
    /// Syntax format version (defaults to 2).
    pub version: u32,

    #[serde(default)]
    /// Optional inheritance chain.
    pub extends: Option<Extends>,

    #[serde(default)]
    /// Whether this syntax is hidden.
    pub hidden: bool,

    #[serde(default)]
    /// Variables used for regex substitution.
    pub variables: HashMap<String, String>,

    /// Contexts keyed by context name.
    pub contexts: HashMap<String, Vec<RawContextPattern>>,
}

fn default_version() -> u32 {
    2
}

#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone)]
/// A single entry in a context's pattern list.
pub enum RawContextPattern {
    /// A meta directive (must appear before non-meta patterns in a context).
    Meta(MetaPattern),
    /// A regex match pattern.
    Match(MatchPattern),
    /// An include pattern.
    Include(IncludePattern),
}

impl<'de> Deserialize<'de> for RawContextPattern {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;
        let Value::Mapping(map) = &value else {
            return Err(serde::de::Error::custom(
                "context patterns must be YAML mappings",
            ));
        };

        let has_key = |k: &str| map.contains_key(Value::String(k.to_string()));

        if has_key("match") {
            let pattern: MatchPattern =
                serde_yaml::from_value(value).map_err(serde::de::Error::custom)?;
            return Ok(Self::Match(pattern));
        }

        if has_key("include") {
            let pattern: IncludePattern =
                serde_yaml::from_value(value).map_err(serde::de::Error::custom)?;
            return Ok(Self::Include(pattern));
        }

        // Everything else in a context list is treated as a meta pattern.
        let meta: MetaPattern = serde_yaml::from_value(Value::Mapping(map.clone()))
            .map_err(serde::de::Error::custom)?;
        Ok(Self::Meta(meta))
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
/// A "meta pattern" that configures context behavior (scopes, prototype include, etc.).
pub struct MetaPattern {
    #[serde(default)]
    /// Scope applied while the context is on the stack.
    pub meta_scope: Option<String>,

    #[serde(default)]
    /// Scope applied to content matched while this context is on the stack.
    pub meta_content_scope: Option<String>,

    #[serde(default)]
    /// Whether this context includes the syntax `prototype`.
    pub meta_include_prototype: Option<bool>,

    #[serde(default)]
    /// Optional scope-clearing directive.
    pub clear_scopes: Option<ClearScopes>,

    #[serde(default)]
    /// In inheritance merges, whether to prepend child patterns.
    pub meta_prepend: Option<bool>,

    #[serde(default)]
    /// In inheritance merges, whether to append child patterns.
    pub meta_append: Option<bool>,

    #[serde(default)]
    /// Optional comment (ignored by the engine).
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
/// Controls how many scopes are cleared when entering a context.
pub enum ClearScopes {
    /// Clear a fixed number of scopes.
    Count(usize),
    /// Clear all scopes (`true`) or none (`false`) depending on Sublime format usage.
    All(bool),
}

#[derive(Debug, Clone, Deserialize)]
pub struct IncludePattern {
    pub include: String,

    #[serde(default)]
    pub apply_prototype: Option<bool>,

    #[serde(default)]
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
/// A `match:` pattern entry.
pub struct MatchPattern {
    #[serde(rename = "match")]
    /// The regex source string.
    pub regex: String,

    #[serde(default)]
    /// Optional scope to apply to the matched text.
    pub scope: Option<String>,

    #[serde(default)]
    /// Per-capture scope specifications.
    pub captures: HashMap<u32, CaptureSpec>,

    #[serde(default)]
    /// Push contexts when the pattern matches.
    pub push: Option<ContextReference>,

    #[serde(default)]
    /// Pop contexts when the pattern matches.
    pub pop: Option<PopAction>,

    #[serde(default)]
    /// Set/replace contexts when the pattern matches.
    pub set: Option<ContextReference>,

    #[serde(default)]
    /// Embed another syntax reference.
    pub embed: Option<String>,

    #[serde(default)]
    /// Scope applied to embedded content.
    pub embed_scope: Option<String>,

    #[serde(default)]
    /// Escape regex used to terminate an embed.
    pub escape: Option<String>,

    #[serde(default)]
    /// Capture specs applied to the escape match.
    pub escape_captures: HashMap<u32, CaptureSpec>,

    #[serde(default)]
    /// Prototype patterns to apply for this match.
    pub with_prototype: Option<Vec<RawContextPattern>>,

    #[serde(default)]
    /// Branch target context names (advanced Sublime feature).
    pub branch: Option<Vec<String>>,

    #[serde(default)]
    /// Branch point name (advanced Sublime feature).
    pub branch_point: Option<String>,

    #[serde(default)]
    /// Fail target (advanced Sublime feature).
    pub fail: Option<String>,

    #[serde(default)]
    /// Optional comment (ignored by the engine).
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
/// Scope specification for a capture group.
pub enum CaptureSpec {
    /// A simple scope string.
    Scope(String),
    /// A scope string with nested capture scopes.
    Complex {
        /// Scope applied to the capture group.
        scope: String,
        #[serde(default)]
        /// Nested capture specs for this capture.
        captures: HashMap<u32, CaptureSpec>,
    },
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
/// Reference to one or more contexts.
pub enum ContextReference {
    /// A single context name.
    Name(String),
    /// Multiple context names.
    Names(Vec<String>),
    /// An inline context definition.
    Inline(Vec<RawContextPattern>),
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
/// Pop behavior for a match pattern.
pub enum PopAction {
    /// Pop if `true` (Sublime uses this as a shorthand).
    Bool(bool),
    /// Pop a fixed number of contexts.
    Count(usize),
}
