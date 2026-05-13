import AppKit
import Foundation

final class LaunchAtLoginManager {

    static let shared = LaunchAtLoginManager()

    private let label = "com.bilel.clipboardy"

    private var plistURL: URL {
        let launchAgents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        return launchAgents.appendingPathComponent("\(label).plist")
    }

    private var executablePath: String? {
        let url = Bundle.main.executableURL
        return url?.path
    }

    func canConfigureForCurrentRun() -> Bool {
        guard let exec = executablePath else { return false }
        return exec.contains(".app/Contents/MacOS/")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    private func installLaunchAgent() {
        guard let execPath = executablePath else { return }

        let fm = FileManager.default
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
        <plist version=\"1.0\">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(execPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>StandardOutPath</key>
          <string>/tmp/\(label).out.log</string>
          <key>StandardErrorPath</key>
          <string>/tmp/\(label).err.log</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            _ = runLaunchCtl(arguments: ["unload", plistURL.path])
            _ = runLaunchCtl(arguments: ["load", plistURL.path])
        } catch {
            print("[LaunchAtLogin] Failed to write plist: \(error)")
        }
    }

    private func removeLaunchAgent() {
        _ = runLaunchCtl(arguments: ["unload", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private func runLaunchCtl(arguments: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = arguments
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }
}
