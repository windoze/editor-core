pub(crate) fn set_current_thread_qos_for_treesitter_worker() {
    // Best effort: lower priority than the UI thread to avoid input jank / CPU spikes.
    //
    // Tests can set this env var because UTILITY QoS may starve CI enough to trip bounded waits.
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
