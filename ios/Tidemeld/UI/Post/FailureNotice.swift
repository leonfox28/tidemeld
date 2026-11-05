import SwiftUI

/// A generic failure notice with its recovery action supplied by the caller.
struct FailureNotice: View {
    let failure: AppFailure
    var onRecover: ((FailureRecovery) -> Void)? = nil
    var body: some View {
        HStack {
            Text(failure.message).font(.footnote).foregroundStyle(AppTheme.error)
            if let recovery = failure.recovery, let onRecover {
                Button(recovery.label) { onRecover(recovery) }.font(.footnote)
            }
        }
    }
}
