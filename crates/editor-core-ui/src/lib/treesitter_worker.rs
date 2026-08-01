use super::*;

#[derive(Debug, Default)]
pub(crate) struct TreeSitterCaptureMapper {
    capture_to_id: HashMap<String, u32>,
    id_to_capture: Vec<String>,
}

impl TreeSitterCaptureMapper {
    /// Base prefix for Tree-sitter highlight capture `StyleId`s.
    pub const BASE: u32 = 0x0500_0000;

    pub fn style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        if let Some(&id) = self.capture_to_id.get(capture_name) {
            return id;
        }
        let idx = self.id_to_capture.len() as u32 + 1;
        let id = Self::BASE | idx;
        self.id_to_capture.push(capture_name.to_string());
        self.capture_to_id.insert(capture_name.to_string(), id);
        id
    }

    pub fn capture_for_style_id(&self, style_id: u32) -> Option<&str> {
        if style_id & 0xFF00_0000 != Self::BASE {
            return None;
        }
        let raw = style_id & 0x00FF_FFFF;
        if raw == 0 {
            return None;
        }
        let idx = raw.saturating_sub(1) as usize;
        self.id_to_capture.get(idx).map(|s| s.as_str())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessingPollResult {
    pub applied: bool,
    pub pending: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TreeSitterProcessingConfig {
    /// Debounce window for running Tree-sitter queries (highlighting/folding).
    pub debounce_ms: u32,
    /// Soft budget for a single query pass; when exceeded, the worker enters a cooldown window
    /// and prefers visible-range queries.
    pub query_budget_ms: u32,
    /// Cooldown window after an over-budget query pass.
    pub cooldown_ms: u32,
    /// When the document exceeds this many Unicode scalar values, prefer visible-range queries.
    pub large_doc_char_threshold: u32,
    /// If true, large documents use visible/prefetch-range queries by default.
    pub prefer_visible_range_on_large_docs: bool,
}

impl Default for TreeSitterProcessingConfig {
    fn default() -> Self {
        Self {
            // One-frame debounce: coalesce bursts without making highlighting feel "late".
            debounce_ms: 16,
            // Anything above ~1 frame is already noticeable for CPU/battery; degrade when exceeded.
            query_budget_ms: 30,
            cooldown_ms: 200,
            large_doc_char_threshold: 200_000,
            prefer_visible_range_on_large_docs: true,
        }
    }
}

pub(crate) enum TreeSitterWorkerMsg {
    Init {
        config: TreeSitterProcessorConfig,
        runtime: TreeSitterProcessingConfig,
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    ApplyDelta {
        version: u64,
        delta: editor_core::delta::TextDelta,
        prefetch_char_range: Option<(usize, usize)>,
    },
    FullSync {
        version: u64,
        text: String,
        prefetch_char_range: Option<(usize, usize)>,
    },
    UpdateRuntimeConfig {
        runtime: TreeSitterProcessingConfig,
    },
    Shutdown,
}

pub(crate) enum TreeSitterWorkerEvent {
    Processed {
        version: u64,
        edits: Vec<ProcessingEdit>,
        update_mode: TreeSitterUpdateMode,
    },
    NeedFullSync,
    Error(String),
}

pub(crate) fn set_current_thread_qos_for_treesitter_worker() {
    // Best effort: lower priority than the UI thread to avoid input jank / CPU spikes.
    //
    // Escape hatch: on some machines the UTILITY QoS class starves this worker badly enough that a
    // single WASM grammar load + parse does not finish within a test's bounded wait window, making
    // the async tree-sitter tests time out. Tests set `EDITOR_CORE_DISABLE_TS_WORKER_QOS=1` to keep
    // the worker at normal priority. This is honored across crates (the env var is read at runtime),
    // unlike a `cfg(test)` gate which only applies to the crate under test.
    #[cfg(target_os = "macos")]
    {
        if std::env::var_os("EDITOR_CORE_DISABLE_TS_WORKER_QOS").is_some() {
            return;
        }
        unsafe {
            let _ = libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_UTILITY, 0);
        }
    }
}

#[derive(Debug)]
pub(crate) struct TreeSitterAsyncWorker {
    pub(crate) tx: mpsc::Sender<TreeSitterWorkerMsg>,
    pub(crate) rx: mpsc::Receiver<TreeSitterWorkerEvent>,
    pub(crate) join: Option<thread::JoinHandle<()>>,
    pub(crate) requested_version: Option<u64>,
    pub(crate) applied_version: Option<u64>,
    pub(crate) last_update_mode: Option<TreeSitterUpdateMode>,
}

impl TreeSitterAsyncWorker {
    pub(crate) fn spawn() -> Self {
        let (tx, rx_worker) = mpsc::channel::<TreeSitterWorkerMsg>();
        let (tx_events, rx) = mpsc::channel::<TreeSitterWorkerEvent>();

        let join = thread::Builder::new()
            .name("editor-core-treesitter-worker".to_string())
            .spawn(move || {
                set_current_thread_qos_for_treesitter_worker();

                let mut processor: Option<TreeSitterProcessor> = None;
                let mut runtime = TreeSitterProcessingConfig::default();

                let mut latest_prefetch_char_range: Option<(usize, usize)> = None;
                let mut latest_doc_char_count: usize = 0;
                let mut latest_version: u64 = 0;
                let mut dirty_for_query: bool = false;
                let mut awaiting_full_sync: bool = false;
                let mut sent_need_full_sync: bool = false;

                let mut debounce_deadline: Option<std::time::Instant> = None;
                let mut cooldown_until: Option<std::time::Instant> = None;
                let mut degraded: bool = false;
                let mut degraded_fast_streak: u32 = 0;

                loop {
                    let now = std::time::Instant::now();
                    let debounce_at = debounce_deadline.unwrap_or(now);
                    let next_action_at = if dirty_for_query {
                        match cooldown_until {
                            Some(cooldown) if cooldown > debounce_at => cooldown,
                            _ => debounce_at,
                        }
                    } else {
                        // No pending query work; block until the next message.
                        std::time::Instant::now()
                    };

                    let msg = if dirty_for_query {
                        let timeout = next_action_at.saturating_duration_since(now);
                        rx_worker.recv_timeout(timeout)
                    } else {
                        rx_worker
                            .recv()
                            .map_err(|_| mpsc::RecvTimeoutError::Disconnected)
                    };

                    match msg {
                        Ok(TreeSitterWorkerMsg::Shutdown) => break,
                        Ok(TreeSitterWorkerMsg::UpdateRuntimeConfig { runtime: next }) => {
                            runtime = next;
                        }
                        Ok(TreeSitterWorkerMsg::Init {
                            config,
                            runtime: next_runtime,
                            version,
                            text,
                            prefetch_char_range,
                        }) => {
                            runtime = next_runtime;
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = text.chars().count();
                            dirty_for_query = false;
                            awaiting_full_sync = false;
                            sent_need_full_sync = false;

                            match TreeSitterProcessor::new(config) {
                                Ok(mut p) => match p.sync_to(version, None, Some(&text)) {
                                    Ok(_) => {
                                        processor = Some(p);
                                        latest_version = version;
                                        dirty_for_query = true;
                                        debounce_deadline = Some(
                                            std::time::Instant::now()
                                                + std::time::Duration::from_millis(
                                                    runtime.debounce_ms as u64,
                                                ),
                                        );
                                    }
                                    Err(e) => {
                                        let _ = tx_events
                                            .send(TreeSitterWorkerEvent::Error(e.to_string()));
                                        processor = Some(p);
                                    }
                                },
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Ok(TreeSitterWorkerMsg::ApplyDelta {
                            version,
                            delta,
                            prefetch_char_range,
                        }) => {
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = delta.after_char_count;

                            if awaiting_full_sync {
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            }

                            let Some(p) = processor.as_mut() else {
                                awaiting_full_sync = true;
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            };

                            match p.sync_to(version, Some(&delta), None) {
                                Ok(_) => {
                                    latest_version = version;
                                    dirty_for_query = true;
                                    debounce_deadline = Some(
                                        std::time::Instant::now()
                                            + std::time::Duration::from_millis(
                                                runtime.debounce_ms as u64,
                                            ),
                                    );
                                }
                                Err(editor_core_treesitter::TreeSitterError::DeltaMismatch) => {
                                    awaiting_full_sync = true;
                                    if !sent_need_full_sync {
                                        let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                        sent_need_full_sync = true;
                                    }
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Ok(TreeSitterWorkerMsg::FullSync {
                            version,
                            text,
                            prefetch_char_range,
                        }) => {
                            latest_prefetch_char_range = prefetch_char_range;
                            latest_doc_char_count = text.chars().count();

                            let Some(p) = processor.as_mut() else {
                                awaiting_full_sync = true;
                                if !sent_need_full_sync {
                                    let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                    sent_need_full_sync = true;
                                }
                                continue;
                            };

                            match p.sync_to(version, None, Some(&text)) {
                                Ok(_) => {
                                    latest_version = version;
                                    awaiting_full_sync = false;
                                    sent_need_full_sync = false;
                                    dirty_for_query = true;
                                    debounce_deadline = Some(
                                        std::time::Instant::now()
                                            + std::time::Duration::from_millis(
                                                runtime.debounce_ms as u64,
                                            ),
                                    );
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            // We reached the debounce/cooldown boundary; run queries if needed.
                            if !dirty_for_query {
                                continue;
                            }
                            if awaiting_full_sync {
                                continue;
                            }
                            if let Some(cooldown) = cooldown_until
                                && std::time::Instant::now() < cooldown
                            {
                                continue;
                            }

                            let Some(p) = processor.as_mut() else {
                                continue;
                            };

                            let large_doc = runtime.prefer_visible_range_on_large_docs
                                && latest_doc_char_count
                                    >= runtime.large_doc_char_threshold as usize;
                            let use_range = if degraded || large_doc {
                                latest_prefetch_char_range
                            } else {
                                None
                            };

                            let t0 = std::time::Instant::now();
                            match p.compute_processing_edits(use_range) {
                                Ok(edits) => {
                                    let dt = t0.elapsed();
                                    let dt_ms = dt.as_secs_f64() * 1000.0;

                                    if dt_ms > runtime.query_budget_ms as f64 {
                                        degraded = true;
                                        degraded_fast_streak = 0;
                                        cooldown_until = Some(
                                            std::time::Instant::now()
                                                + std::time::Duration::from_millis(
                                                    runtime.cooldown_ms as u64,
                                                ),
                                        );
                                    } else if degraded {
                                        degraded_fast_streak =
                                            degraded_fast_streak.saturating_add(1);
                                        if degraded_fast_streak >= 5 {
                                            degraded = false;
                                            degraded_fast_streak = 0;
                                        }
                                    }

                                    let _ = tx_events.send(TreeSitterWorkerEvent::Processed {
                                        version: latest_version,
                                        edits,
                                        update_mode: p.last_update_mode(),
                                    });
                                    dirty_for_query = false;
                                }
                                Err(editor_core_treesitter::TreeSitterError::DeltaMismatch) => {
                                    awaiting_full_sync = true;
                                    if !sent_need_full_sync {
                                        let _ = tx_events.send(TreeSitterWorkerEvent::NeedFullSync);
                                        sent_need_full_sync = true;
                                    }
                                }
                                Err(e) => {
                                    let _ =
                                        tx_events.send(TreeSitterWorkerEvent::Error(e.to_string()));
                                }
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    }
                }
            })
            .ok();

        Self {
            tx,
            rx,
            join,
            requested_version: None,
            applied_version: None,
            last_update_mode: None,
        }
    }

    pub(crate) fn is_pending(&self) -> bool {
        match (self.requested_version, self.applied_version) {
            (Some(req), Some(applied)) => applied < req,
            (Some(_), None) => true,
            _ => false,
        }
    }
}

impl Drop for TreeSitterAsyncWorker {
    fn drop(&mut self) {
        let _ = self.tx.send(TreeSitterWorkerMsg::Shutdown);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}
