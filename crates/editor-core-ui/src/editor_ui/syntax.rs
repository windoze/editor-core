use super::*;

impl EditorUi {
    pub fn set_sublime_syntax_yaml(&mut self, yaml: &str) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_str(yaml)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.sublime = Some(SublimeProcessor::new(syntax, set));
        }
        self.refresh_processing()
    }

    pub fn set_sublime_syntax_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_path(path)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.sublime = Some(SublimeProcessor::new(syntax, set));
        }
        self.refresh_processing()
    }

    pub fn disable_sublime_syntax(&mut self) {
        let mut doc = self.lock_doc();
        doc.sublime = None;
    }

    pub fn sublime_scope_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.sublime
            .as_ref()
            .and_then(|p| p.scope_mapper.scope_for_style_id(style_id))
            .map(|s| s.to_string())
    }

    pub fn sublime_style_id_for_scope(&mut self, scope: &str) -> Result<u32, UiError> {
        let mut doc = self.lock_doc();
        let Some(proc) = doc.sublime.as_mut() else {
            return Err(UiError::Processor(
                "sublime syntax processor is not enabled".to_string(),
            ));
        };
        Ok(proc.scope_mapper.style_id_for_scope(scope))
    }

    /// Replace the Tree-sitter registry for this document with a schema-versioned JSON string.
    ///
    /// This is designed for Swift ↔ Rust FFI where passing maps directly is inconvenient.
    pub fn set_treesitter_registry_json(&mut self, registry_json: &str) -> Result<(), UiError> {
        let registry = TreeSitterRegistry::from_json_str(registry_json)
            .map_err(|e: TreeSitterRegistryError| UiError::Processor(e.to_string()))?;
        let mut doc = self.lock_doc();
        doc.treesitter_registry = registry;
        Ok(())
    }

    /// Enable Tree-sitter highlighting/folding using the current registry and a Tree-sitter
    /// `language_id` (e.g. `"rust"`).
    pub fn set_treesitter_language(&mut self, language_id: &str) -> Result<(), UiError> {
        let language_config = {
            let doc = self.lock_doc();
            doc.treesitter_registry
                .languages
                .get(language_id)
                .cloned()
                .ok_or_else(|| {
                    UiError::Processor(format!(
                        "unknown tree-sitter language_id (not in registry): {language_id}"
                    ))
                })?
        };

        let indenter = load_indenter_config_from_config(language_id, &language_config)
            .ok()
            .flatten()
            .and_then(|cfg| {
                if cfg.indents_query.trim().is_empty() {
                    None
                } else {
                    TreeSitterIndenter::new(cfg).ok()
                }
            });

        let mut config = load_processor_config_from_config(language_id, &language_config)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        let capture_names = config
            .highlights_capture_names()
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let (capture_styles, runtime, text, version) = {
            let mut doc = self.lock_doc();
            let mut capture_styles = BTreeMap::<String, u32>::new();
            for name in &capture_names {
                let style_id = doc.treesitter_capture_mapper.style_id_for_capture(name);
                capture_styles.insert(name.to_string(), style_id);
            }

            doc.treesitter = None;
            doc.treesitter_indenter = None;
            doc.apply_processing_edits(
                self.view_id,
                [
                    ProcessingEdit::ClearStyleLayer {
                        layer: StyleLayerId::TREE_SITTER,
                    },
                    ProcessingEdit::ClearFoldingRegions,
                ],
            )?;

            let text = doc
                .ws
                .buffer_text(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
            let version = doc.treesitter_doc_version;
            let runtime = doc.treesitter_processing_config;
            (capture_styles, runtime, text, version)
        };

        config.capture_styles = capture_styles;

        let mut worker = TreeSitterAsyncWorker::spawn();
        worker.requested_version = Some(version);
        worker
            .tx
            .send(TreeSitterWorkerMsg::Init {
                config,
                runtime,
                version,
                text,
                prefetch_char_range,
            })
            .map_err(|_| UiError::Processor("failed to start tree-sitter worker".to_string()))?;
        {
            let mut doc = self.lock_doc();
            doc.treesitter = Some(worker);
            doc.treesitter_indenter = indenter;
        }
        Ok(())
    }

    /// Enable Tree-sitter highlighting/folding for a file path by resolving the extension via
    /// the current registry.
    pub fn set_treesitter_for_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let language_id = {
            let doc = self.lock_doc();
            doc.treesitter_registry
                .language_id_for_path(path)
                .map(|s| s.to_string())
        }
        .ok_or_else(|| {
            UiError::Processor(format!(
                "no tree-sitter language_id mapped for path: {}",
                path.display()
            ))
        })?;

        self.set_treesitter_language(language_id.as_str())
    }

    /// Backwards-compatible alias: treat `pack_id` as `language_id`.
    pub fn set_treesitter_query_pack(&mut self, pack_id: &str) -> Result<(), UiError> {
        self.set_treesitter_language(pack_id)
    }

    /// Backwards-compatible alias: `rust` language id.
    pub fn set_treesitter_rust_default(&mut self) -> Result<(), UiError> {
        self.set_treesitter_language("rust")
    }

    pub fn disable_treesitter(&mut self) {
        let mut doc = self.lock_doc();
        doc.treesitter = None;
        doc.treesitter_indenter = None;
    }
}
