import XCTest

/// Guards the cold-launch budget in docs/performance.md. Meaningful on a device with a Release build;
/// on the simulator use it to spot regressions, not as the absolute number.
/// Slow (5 launches), so opt-in: `TEST_RUNNER_RUN_PERF=1 xcodebuild test …`.
final class LaunchPerformanceTests: XCTestCase {
    @MainActor
    func testLaunchWithCachedList() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_PERF"] != nil, "set TEST_RUNNER_RUN_PERF=1")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seeded"]
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
    }
}
