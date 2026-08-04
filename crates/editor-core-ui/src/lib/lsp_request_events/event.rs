#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorLspRequestEvent {
    pub sequence: u64,
    pub family: String,
    pub title: String,
    pub slot: String,
    pub method: String,
    pub view_id: u64,
    pub request_id: u64,
    pub phase: String,
    pub status: String,
    pub result_sequence: Option<u64>,
    pub error_code: Option<i64>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct EditorLspRequestEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<EditorLspRequestEvent>,
}
