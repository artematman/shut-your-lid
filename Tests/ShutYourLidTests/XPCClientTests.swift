import Foundation
import Testing
@testable import LidModeFeature

/// Regression for the 0.3.8 build 14 first-launch crash: NSXPC invokes the
/// proxy error handler and the connection's invalidation handler on its own
/// background queue; closures inheriting MainActor isolation trapped in
/// `_dispatch_assert_queue_fail`. A real NSXPCConnection to a Mach service
/// that does not exist forces exactly those callbacks.
@MainActor @Suite("XPC client callbacks", .serialized)
struct XPCClientTests {
    private func missingService() -> String { "com.artemkharitonov.shutyourlid.tests.missing.\(UUID().uuidString)" }

    @Test("a missing helper answers nil from the background error path, without crashing")
    func missingHelperReturnsNil() async {
        let client = LidPowerClient(machService: missingService())
        let start = ContinuousClock.now
        let status = await client.call(.status)
        #expect(status == nil)
        // The error callback, not the 15 s timeout, ended the call.
        #expect(ContinuousClock.now - start < .seconds(10))
        // The invalidation handler also ran on NSXPC's queue and hopped back to drop the connection.
        let deadline = ContinuousClock.now + .seconds(10)
        while client.hasConnection, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!client.hasConnection)
    }

    @Test("every request kind, repeated and in parallel, completes exactly once with nil")
    func repeatedAndParallelCalls() async {
        let client = LidPowerClient(machService: missingService())
        let requests: [LidModeModel.Request] = [.status, .heartbeat, .disable, .updateDuration(maxMinutes: 30), .enable(maxMinutes: 30, batteryFloor: 10)]
        for request in requests {
            // Sequential: after invalidation the client must build a fresh connection.
            #expect(await client.call(request) == nil)
        }
        // Parallel: 24 calls in flight on one connection, all failing on XPC's queue.
        let tasks = (0..<24).map { index in Task { await client.call(requests[index % requests.count]) } }
        var results: [LidModeStatus?] = []
        for task in tasks { results.append(await task.value) }
        // A double resume would trap in CheckedContinuation; a lost one would hang the group.
        #expect(results.count == 24 && results.allSatisfy { $0 == nil })
    }
}
