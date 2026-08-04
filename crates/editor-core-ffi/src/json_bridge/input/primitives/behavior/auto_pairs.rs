use super::*;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiAutoPair {
    open: String,
    close: String,
}

impl FfiAutoPair {
    pub(crate) fn try_into_core(self) -> Result<AutoPair, String> {
        Ok(AutoPair {
            open: single_char(&self.open, "auto pair open")?,
            close: single_char(&self.close, "auto pair close")?,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FfiAutoPairsConfig {
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    pairs: Option<Vec<FfiAutoPair>>,
    #[serde(default)]
    wrap_selection: Option<bool>,
    #[serde(default)]
    skip_over_closing: Option<bool>,
    #[serde(default)]
    delete_pair: Option<bool>,
}

impl FfiAutoPairsConfig {
    pub(crate) fn try_into_core(self) -> Result<AutoPairsConfig, String> {
        let mut cfg = AutoPairsConfig::default();
        if let Some(enabled) = self.enabled {
            cfg.enabled = enabled;
        }
        if let Some(pairs) = self.pairs {
            cfg.pairs = pairs
                .into_iter()
                .map(FfiAutoPair::try_into_core)
                .collect::<Result<Vec<_>, _>>()?;
        }
        if let Some(wrap_selection) = self.wrap_selection {
            cfg.wrap_selection = wrap_selection;
        }
        if let Some(skip_over_closing) = self.skip_over_closing {
            cfg.skip_over_closing = skip_over_closing;
        }
        if let Some(delete_pair) = self.delete_pair {
            cfg.delete_pair = delete_pair;
        }
        Ok(cfg)
    }
}
