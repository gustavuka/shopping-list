import Darwin
import Foundation
import OSLog

/// Logs time to first frame once per launch, to keep an eye on the 400 ms budget (docs/performance.md).
/// On in Debug; in Release pass `-measureLaunch`. For real numbers use Instruments' App Launch template
/// on a device — simulator timings are inflated.
@MainActor
enum LaunchTimer {
    private static var appStart: Date?
    private static var reported = false

    private static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.arguments.contains("-measureLaunch")
        #endif
    }

    /// Call first thing in `App.init`.
    static func appDidStart() {
        guard isEnabled else { return }
        appStart = Date()
    }

    /// Logs two numbers: since process start (includes dyld and, on the simulator, a large spawn
    /// overhead) and since `App.init` (the part our code controls).
    static func firstFrameRendered(_ screen: String) {
        guard isEnabled, !reported, let appStart, let processStart = processStartDate() else { return }
        reported = true
        let now = Date()
        let total = Int(now.timeIntervalSince(processStart) * 1000)
        let ours = Int(now.timeIntervalSince(appStart) * 1000)
        Logger.performance.notice(
            "First frame (\(screen, privacy: .public)): \(total) ms since process start, \(ours) ms since App.init"
        )
    }

    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
