use crate::sublime_syntax::compiler::SublimeSyntax;
use crate::sublime_syntax::definition::{Extends, RawContextPattern, SyntaxDefinition};
use crate::sublime_syntax::error::SublimeSyntaxError;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Debug, Default)]
/// A collection of compiled Sublime syntax definitions, with support for resolving `extends` and `include`.
pub struct SublimeSyntaxSet {
    search_paths: Vec<PathBuf>,
    compiled_by_scope: HashMap<String, Arc<SublimeSyntax>>,
    compiled_by_reference: HashMap<String, Arc<SublimeSyntax>>,
    merged_definition_cache: HashMap<String, SyntaxDefinition>,
}

impl SublimeSyntaxSet {
    /// Create an empty syntax set.
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a filesystem search path used to resolve `Packages/...` references.
    pub fn add_search_path(&mut self, path: impl Into<PathBuf>) {
        self.search_paths.push(path.into());
    }

    /// Get a compiled syntax by its `scope` (e.g. `"source.rust"`).
    pub fn get_by_scope(&self, scope: &str) -> Option<Arc<SublimeSyntax>> {
        self.compiled_by_scope.get(scope).cloned()
    }

    /// Loads a syntax from a YAML string and returns the compiled result.
    ///
    /// If the syntax uses `extends: ...`, it will be resolved via `search_paths`.
    pub fn load_from_str(&mut self, yaml: &str) -> Result<Arc<SublimeSyntax>, SublimeSyntaxError> {
        let definition: SyntaxDefinition = serde_yaml::from_str(yaml)?;
        let resolved = self.resolve_inheritance(definition, &mut Vec::new())?;
        let compiled = Arc::new(SublimeSyntax::compile(resolved)?);
        self.compiled_by_scope
            .insert(compiled.scope.clone(), compiled.clone());
        Ok(compiled)
    }

    /// Loads a syntax from a filesystem path and returns the compiled result.
    pub fn load_from_path(
        &mut self,
        path: impl AsRef<Path>,
    ) -> Result<Arc<SublimeSyntax>, SublimeSyntaxError> {
        let path = path.as_ref();
        let yaml = std::fs::read_to_string(path)?;
        let definition: SyntaxDefinition = serde_yaml::from_str(&yaml)?;
        let resolved = self.resolve_inheritance(definition, &mut Vec::new())?;
        let compiled = Arc::new(SublimeSyntax::compile(resolved)?);
        let reference = path.to_string_lossy().to_string();

        self.compiled_by_reference
            .insert(reference, compiled.clone());
        self.compiled_by_scope
            .insert(compiled.scope.clone(), compiled.clone());
        Ok(compiled)
    }

    /// Loads (or returns a cached) compiled syntax by a Sublime reference string.
    ///
    /// Supported forms:
    /// - `scope:source.rust` (lookup by scope)
    /// - `Packages/JavaScript/JavaScript.sublime-syntax` (filesystem search)
    /// - absolute or relative filesystem paths
    pub fn load_by_reference(
        &mut self,
        reference: &str,
    ) -> Result<Arc<SublimeSyntax>, SublimeSyntaxError> {
        if let Some(s) = self.compiled_by_reference.get(reference) {
            return Ok(s.clone());
        }

        if let Some(scope) = reference.strip_prefix("scope:") {
            return self
                .get_by_scope(scope)
                .ok_or_else(|| SublimeSyntaxError::UnknownSyntaxReference(reference.to_string()));
        }

        let path = self
            .resolve_reference_to_path(reference)
            .ok_or_else(|| SublimeSyntaxError::UnknownSyntaxReference(reference.to_string()))?;
        let yaml = std::fs::read_to_string(&path)?;
        let definition: SyntaxDefinition = serde_yaml::from_str(&yaml)?;
        let resolved = self.resolve_inheritance(definition, &mut Vec::new())?;
        let compiled = Arc::new(SublimeSyntax::compile(resolved)?);

        self.compiled_by_reference
            .insert(reference.to_string(), compiled.clone());
        self.compiled_by_reference
            .insert(path.to_string_lossy().to_string(), compiled.clone());
        self.compiled_by_scope
            .insert(compiled.scope.clone(), compiled.clone());
        Ok(compiled)
    }

    fn resolve_reference_to_path(&self, reference: &str) -> Option<PathBuf> {
        let path = PathBuf::from(reference);
        if path.is_absolute() && path.exists() {
            return Some(path);
        }

        for base in &self.search_paths {
            let candidate = base.join(reference);
            if candidate.exists() {
                return Some(candidate);
            }
        }

        if path.exists() {
            return Some(path);
        }

        None
    }

    fn resolve_inheritance(
        &mut self,
        mut definition: SyntaxDefinition,
        stack: &mut Vec<String>,
    ) -> Result<SyntaxDefinition, SublimeSyntaxError> {
        let Some(extends) = definition.extends.clone() else {
            return Ok(definition);
        };

        let parent_refs: Vec<String> = match extends {
            Extends::One(s) => vec![s],
            Extends::Many(v) => v,
        };

        let mut merged_vars = HashMap::<String, String>::new();
        let mut merged_contexts = HashMap::<String, Vec<RawContextPattern>>::new();

        for parent_ref in &parent_refs {
            let parent_def = self.load_merged_definition_by_reference(parent_ref, stack)?;
            for (k, v) in parent_def.variables {
                merged_vars.insert(k, v);
            }
            for (k, v) in parent_def.contexts {
                merged_contexts.insert(k, v);
            }
        }

        for (k, v) in definition.variables.drain() {
            merged_vars.insert(k, v);
        }

        for (ctx_name, child_patterns) in definition.contexts.drain() {
            if let Some(parent_patterns) = merged_contexts.get(&ctx_name).cloned() {
                let (prepend, append) = inheritance_directives(&child_patterns)?;
                if prepend || append {
                    let (parent_meta, parent_rest) = split_meta_patterns(&parent_patterns)?;
                    let (child_meta, child_rest) = split_meta_patterns(&child_patterns)?;

                    let mut merged = Vec::new();
                    merged.extend(parent_meta);
                    merged.extend(child_meta);

                    if prepend {
                        merged.extend(child_rest);
                        merged.extend(parent_rest);
                    } else {
                        merged.extend(parent_rest);
                        merged.extend(child_rest);
                    }

                    merged_contexts.insert(ctx_name, merged);
                } else {
                    merged_contexts.insert(ctx_name, child_patterns);
                }
            } else {
                merged_contexts.insert(ctx_name, child_patterns);
            }
        }

        definition.variables = merged_vars;
        definition.contexts = merged_contexts;
        definition.extends = None;
        Ok(definition)
    }

    fn load_merged_definition_by_reference(
        &mut self,
        reference: &str,
        stack: &mut Vec<String>,
    ) -> Result<SyntaxDefinition, SublimeSyntaxError> {
        if let Some(def) = self.merged_definition_cache.get(reference) {
            return Ok(def.clone());
        }

        if stack.contains(&reference.to_string()) {
            return Err(SublimeSyntaxError::InheritanceCycle(reference.to_string()));
        }
        stack.push(reference.to_string());

        let path = self
            .resolve_reference_to_path(reference)
            .ok_or_else(|| SublimeSyntaxError::UnknownSyntaxReference(reference.to_string()))?;
        let yaml = std::fs::read_to_string(&path)?;
        let definition: SyntaxDefinition = serde_yaml::from_str(&yaml)?;
        let merged = self.resolve_inheritance(definition, stack)?;

        stack.pop();
        self.merged_definition_cache
            .insert(reference.to_string(), merged.clone());
        Ok(merged)
    }
}

fn inheritance_directives(
    patterns: &[RawContextPattern],
) -> Result<(bool, bool), SublimeSyntaxError> {
    let mut prepend = false;
    let mut append = false;

    for p in patterns {
        match p {
            RawContextPattern::Meta(m) => {
                if let Some(v) = m.meta_prepend {
                    prepend = v;
                }
                if let Some(v) = m.meta_append {
                    append = v;
                }
            }
            _ => break,
        }
    }

    if prepend && append {
        return Err(SublimeSyntaxError::Unsupported(
            "meta_prepend and meta_append together",
        ));
    }

    Ok((prepend, append))
}

fn split_meta_patterns(
    patterns: &[RawContextPattern],
) -> Result<(Vec<RawContextPattern>, Vec<RawContextPattern>), SublimeSyntaxError> {
    let mut meta = Vec::new();
    let mut rest = Vec::new();
    let mut in_meta = true;

    for p in patterns {
        match p {
            RawContextPattern::Meta(_) if in_meta => meta.push(p.clone()),
            RawContextPattern::Meta(_) => {
                return Err(SublimeSyntaxError::Unsupported(
                    "meta patterns must be listed first in a context",
                ));
            }
            _ => {
                in_meta = false;
                rest.push(p.clone());
            }
        }
    }

    Ok((meta, rest))
}
