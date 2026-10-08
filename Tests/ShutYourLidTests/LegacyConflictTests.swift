import Foundation
import Testing
@testable import LidModeFeature

@Suite("Legacy power controller detection")
struct LegacyConflictTests {
    @Test("An open Island window alone does not block the standalone app")
    func unrelatedUI() {
        let running = ["/Applications/Island Pro Beta.app/Contents/MacOS/IslandPro", "/Applications/Island Pro.app/Contents/MacOS/NotchFlowApp"]
        let conflict = LegacyModeConflict.isPresent { path, arguments in
            guard path == "/usr/bin/pgrep" else { return false }
            if arguments.first == "-x" { return running.contains { URL(fileURLWithPath: $0).lastPathComponent == arguments[1] } }
            return running.contains { $0.range(of: arguments[1], options: .regularExpression) != nil }
        }
        #expect(!conflict)
    }

    @Test(arguments: ["local.artem.islandpro.beta.power", "local.artem.islandpro.power"])
    func registeredDaemonBlocks(_ label: String) {
        #expect(LegacyModeConflict.isPresent { path, arguments in
            path == "/bin/launchctl" && arguments == ["print", "system/" + label]
        })
    }

    @Test("A helper process still blocks even when its service is not listed")
    func runningHelperBlocks() {
        #expect(LegacyModeConflict.isPresent { path, arguments in
            path == "/usr/bin/pgrep" && arguments == ["-x", "IslandPowerHelper"]
        })
    }
}
