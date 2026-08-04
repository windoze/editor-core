import Foundation

extension AttoWorkspaceEditPreview {
    var canResolveConflictAndRetry: Bool {
        requestRetryDescriptor?.canRerun ?? true
    }

    var requestRetryUnavailableReason: String? {
        requestRetryDescriptor?.invalidationReasonText
    }

    var requestRetrySummaryLine: String? {
        requestRetryDescriptor?.requestSummaryText
    }

    var requestRetryUnavailableStatusText: String? {
        guard let descriptor = requestRetryDescriptor,
              descriptor.canRerun == false
        else {
            return nil
        }
        return descriptor.retryUnavailableStatusText
    }

    var requestRetryUnavailableToolTip: String? {
        guard let descriptor = requestRetryDescriptor,
              let reason = descriptor.invalidationReasonText
        else {
            return nil
        }
        return "Cannot retry \(descriptor.label): \(reason)"
    }
}
