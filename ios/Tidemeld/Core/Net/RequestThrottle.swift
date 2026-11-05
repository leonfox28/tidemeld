import Foundation

/// Caps concurrent requests and spaces out their starts, so the app never sends
/// Weibo a burst; backs off further when Weibo signals rate limiting.
actor RequestThrottle {
    let maxConcurrent: Int
    let minInterval: Duration
    private let clock = ContinuousClock()

    private var running = 0
    /// Waiters for a slot, first come first served.
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var nextStart: ContinuousClock.Instant?
    private var backOffUntil: ContinuousClock.Instant?
    private var backOff: Duration = .zero

    private static let firstBackOff: Duration = .seconds(5)
    private static let maxBackOff: Duration = .seconds(60)

    init(maxConcurrent: Int = 2, minInterval: Duration = .milliseconds(500)) {
        self.maxConcurrent = maxConcurrent
        self.minInterval = minInterval
    }

    /// Waits for a free slot and the next allowed start time.
    ///
    /// Every call that returns must be paired with exactly one [release].
    func acquire() async {
        if running < maxConcurrent {
            running += 1
        } else {
            // [release] hands its slot straight over.
            await withCheckedContinuation { waiters.append($0) }
        }
        let now = clock.now
        var start = now
        if let nextStart { start = max(start, nextStart) }
        if let backOffUntil { start = max(start, backOffUntil) }
        nextStart = start + minInterval
        if start > now { try? await clock.sleep(until: start) }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Delays later requests, doubling the pause on each consecutive call.
    func backOffMore() {
        backOff = backOff == .zero ? Self.firstBackOff : min(backOff * 2, Self.maxBackOff)
        backOffUntil = clock.now + backOff
    }

    func resetBackOff() {
        backOff = .zero
    }
}
