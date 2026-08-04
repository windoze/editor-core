use super::*;

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub(crate) enum FfiProcessingEditInput {
    ReplaceStyleLayer {
        layer: u32,
        intervals: Vec<FfiIntervalInput>,
    },
    ClearStyleLayer {
        layer: u32,
    },
    ReplaceFoldingRegions {
        regions: Vec<FfiFoldRegionInput>,
        #[serde(default)]
        preserve_collapsed: bool,
    },
    ClearFoldingRegions,
    ReplaceDiagnostics {
        diagnostics: Vec<FfiDiagnosticInput>,
    },
    ClearDiagnostics,
    ReplaceDecorations {
        layer: u32,
        decorations: Vec<FfiDecorationInput>,
    },
    ClearDecorations {
        layer: u32,
    },
    ReplaceDocumentSymbols {
        symbols: Vec<FfiDocumentSymbolInput>,
    },
    ClearDocumentSymbols,
}

impl FfiProcessingEditInput {
    fn into_core(self) -> ProcessingEdit {
        match self {
            Self::ReplaceStyleLayer { layer, intervals } => ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::new(layer),
                intervals: intervals.into_iter().map(Into::into).collect(),
            },
            Self::ClearStyleLayer { layer } => ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::new(layer),
            },
            Self::ReplaceFoldingRegions {
                regions,
                preserve_collapsed,
            } => ProcessingEdit::ReplaceFoldingRegions {
                regions: regions.into_iter().map(Into::into).collect(),
                preserve_collapsed,
            },
            Self::ClearFoldingRegions => ProcessingEdit::ClearFoldingRegions,
            Self::ReplaceDiagnostics { diagnostics } => ProcessingEdit::ReplaceDiagnostics {
                diagnostics: diagnostics.into_iter().map(Into::into).collect(),
            },
            Self::ClearDiagnostics => ProcessingEdit::ClearDiagnostics,
            Self::ReplaceDecorations { layer, decorations } => ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::new(layer),
                decorations: decorations.into_iter().map(Into::into).collect(),
            },
            Self::ClearDecorations { layer } => ProcessingEdit::ClearDecorations {
                layer: DecorationLayerId::new(layer),
            },
            Self::ReplaceDocumentSymbols { symbols } => ProcessingEdit::ReplaceDocumentSymbols {
                symbols: DocumentOutline::new(symbols.into_iter().map(Into::into).collect()),
            },
            Self::ClearDocumentSymbols => ProcessingEdit::ClearDocumentSymbols,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub(crate) enum FfiProcessingEditsInput {
    One(FfiProcessingEditInput),
    Many(Vec<FfiProcessingEditInput>),
}

impl FfiProcessingEditsInput {
    pub(crate) fn into_core(self) -> Vec<ProcessingEdit> {
        match self {
            Self::One(edit) => vec![edit.into_core()],
            Self::Many(edits) => edits
                .into_iter()
                .map(FfiProcessingEditInput::into_core)
                .collect(),
        }
    }
}
