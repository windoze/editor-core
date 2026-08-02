use crate::lsp_result_events::EditorLspResultEventStatus;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EditorLspRequestEventPhase {
    Started,
    Completed,
}

impl EditorLspRequestEventPhase {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Started => "started",
            Self::Completed => "completed",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EditorLspRequestEventStatus {
    Pending,
    Success,
    Empty,
    Error,
    Stale,
    Mismatched,
    Canceled,
    Timeout,
}

impl EditorLspRequestEventStatus {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Success => "success",
            Self::Empty => "empty",
            Self::Error => "error",
            Self::Stale => "stale",
            Self::Mismatched => "mismatched",
            Self::Canceled => "canceled",
            Self::Timeout => "timeout",
        }
    }

    pub(crate) fn from_result_status(status: EditorLspResultEventStatus) -> Self {
        match status {
            EditorLspResultEventStatus::Success => Self::Success,
            EditorLspResultEventStatus::Empty => Self::Empty,
            EditorLspResultEventStatus::Error => Self::Error,
        }
    }
}
