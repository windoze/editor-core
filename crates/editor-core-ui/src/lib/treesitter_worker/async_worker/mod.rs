mod thread_loop;

use super::*;

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
            .spawn(move || thread_loop::run(rx_worker, tx_events))
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
