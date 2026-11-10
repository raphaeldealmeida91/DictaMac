import Darwin
import Foundation

struct SafeModeManager: Sendable {
    let markerURL: URL

    static func live() throws -> SafeModeManager {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("DictaMac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SafeModeManager(markerURL: directory.appendingPathComponent("running.marker"))
    }

    func detectAbnormalExitAndMarkRunning() throws -> Bool {
        let abnormalExit = FileManager.default.fileExists(atPath: markerURL.path)
        let data = Data("pid=\(getpid())\n".utf8)
        try data.write(to: markerURL, options: .atomic)
        return abnormalExit
    }

    func markCleanExit() throws {
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return }
        try FileManager.default.removeItem(at: markerURL)
    }
}
