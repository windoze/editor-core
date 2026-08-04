use super::*;

impl EditorUi {
    pub fn set_treesitter_processing_config(
        &mut self,
        runtime: TreeSitterProcessingConfig,
    ) -> Result<(), UiError> {
        let mut doc = self.lock_doc();
        doc.treesitter_processing_config = runtime;
        if let Some(worker) = doc.treesitter.as_mut() {
            worker
                .tx
                .send(TreeSitterWorkerMsg::UpdateRuntimeConfig { runtime })
                .map_err(|_| {
                    UiError::Processor("failed to update tree-sitter runtime config".to_string())
                })?;
        }
        Ok(())
    }
}
