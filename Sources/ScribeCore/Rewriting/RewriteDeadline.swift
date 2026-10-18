import Foundation
import Synchronization

/// Return at the deadline even while a library is finishing a non-cancellable model load
/// or GPU operation. Cancel the worker; it checks cancellation before starting generation.
enum RewriteDeadline {
    static func run(timeout: Duration, operation: @escaping @Sendable () async throws -> String) async throws -> String {
        let result = PendingRewrite()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                result.install(continuation)
                let work = Task {
                    do { result.complete(.success(try await operation())) }
                    catch { result.complete(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        result.complete(.failure(RewriteError.timedOut))
                    } catch { /* Winning work or caller cancellation stopped the timer. */ }
                }
                result.track(work: work, timer: timer)
            }
        } onCancel: { result.complete(.failure(CancellationError())) }
    }
}

private final class PendingRewrite: Sendable {
    private struct State {
        var result: Result<String, Error>?
        var continuation: CheckedContinuation<String, Error>?
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
    }
    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<String, Error>) {
        let completed = state.withLock { state -> Result<String, Error>? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil as Result<String, Error>?
        }
        if let completed { continuation.resume(with: completed) }
    }

    func track(work: Task<Void, Never>, timer: Task<Void, Never>) {
        let finished = state.withLock { state in
            guard state.result == nil else { return true }
            state.work = work
            state.timer = timer
            return false
        }
        if finished { work.cancel(); timer.cancel() }
    }

    func complete(_ result: Result<String, Error>) {
        let pending = state.withLock { state -> State? in
            guard state.result == nil else { return nil }
            let pending = state
            state.result = result
            state.continuation = nil
            state.work = nil
            state.timer = nil
            return pending
        }
        pending?.work?.cancel()
        pending?.timer?.cancel()
        pending?.continuation?.resume(with: result)
    }
}
