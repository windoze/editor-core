use thiserror::Error;

#[derive(Debug, Error)]
/// Errors produced by the `.sublime-syntax` loader/compiler/highlighter.
pub enum SublimeSyntaxError {
    #[error("YAML parse error: {0}")]
    /// YAML parsing failed.
    Yaml(#[from] serde_yaml::Error),

    #[error("I/O error: {0}")]
    /// Filesystem I/O failed.
    Io(#[from] std::io::Error),

    #[error("missing required field: {0}")]
    /// A required field was missing from a syntax definition.
    MissingField(&'static str),

    #[error("unknown syntax reference: {0}")]
    /// An `include`/reference could not be resolved.
    UnknownSyntaxReference(String),

    #[error("unknown context '{0}'")]
    /// A referenced context name does not exist.
    UnknownContext(String),

    #[error("unknown variable '{0}'")]
    /// A referenced variable name does not exist.
    UnknownVariable(String),

    #[error("circular variable reference '{0}'")]
    /// Variable expansion loop detected.
    CircularVariableReference(String),

    #[error("inheritance cycle detected involving '{0}'")]
    /// An `extends` chain formed a cycle.
    InheritanceCycle(String),

    #[error("regex compile error for pattern '{pattern}': {message}")]
    /// A regex pattern failed to compile.
    RegexCompile {
        /// The regex pattern string.
        pattern: String,
        /// The compiler error message.
        message: String,
    },

    #[error("unsupported feature: {0}")]
    /// A feature from the Sublime syntax format is not implemented.
    Unsupported(&'static str),
}
