import Foundation

/// A platform converts its errors to presentation data; shared UI knows no API types.
protocol UserFacingFailure: Error {
    var appFailure: AppFailure { get }
}

enum FailureRecovery: Sendable, Equatable {
    case signIn
    case verify(URL)
    var label: String {
        switch self {
        case .signIn: "重新登录"
        case .verify: "去验证"
        }
    }
}

struct AppFailure: Error, Sendable, Equatable, UserFacingFailure {
    let message: String
    var recovery: FailureRecovery? = nil
    var isNetwork = false
    var isCancelled = false
    var appFailure: AppFailure { self }
    static let network = AppFailure(message: "网络连接失败，请检查网络", isNetwork: true)
    static let cancelled = AppFailure(message: "已取消", isCancelled: true)
    static func of(_ error: Error) -> AppFailure {
        if let failure = error as? any UserFacingFailure { return failure.appFailure }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
        if error is URLError { return .network }
        return AppFailure(message: "加载失败")
    }
}
