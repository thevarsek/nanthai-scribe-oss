import Foundation
import Testing
@testable import ScribeCore

struct RewriteDeadlineTests {
    @Test func deadlineDoesNotWaitForUncooperativeModelLoader() async {
        let start = ContinuousClock.now
        do {
            _ = try await RewriteDeadline.run(timeout: .milliseconds(20)) {
                // Simulates a library operation that does not observe caller cancellation.
                await Task.detached { try? await Task.sleep(for: .milliseconds(300)) }.value
                return "late"
            }
            Issue.record("Expected a timeout")
        } catch RewriteError.timedOut {
            #expect(start.duration(to: .now) < .milliseconds(250))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func propagatesCallerCancellation() async {
        let work = Task {
            try await RewriteDeadline.run(timeout: .seconds(30)) {
                try await Task.sleep(for: .seconds(30))
                return "late"
            }
        }
        work.cancel()
        do { _ = try await work.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        catch { Issue.record("Unexpected error: \(error)") }
    }
}
