import AppKit
import Foundation
import CoreFoundation

let fm = FileManager.default
let bundleID = "com.moyu.motranslate"
struct DeployError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func fail(_ message: String) throws -> Never { throw DeployError(message: message) }

func isOurTile(_ tile: [String: Any], appURL: URL) -> Bool {
    guard let data = tile["tile-data"] as? [String: Any] else { return false }
    if data["bundle-identifier"] as? String == bundleID { return true }
    guard let file = data["file-data"] as? [String: Any],
          let value = file["_CFURLString"] as? String,
          let url = URL(string: value) else { return false }
    return url.standardizedFileURL == appURL.standardizedFileURL
        || Bundle(url: url)?.bundleIdentifier == bundleID
}

func updatedTiles(_ tiles: [[String: Any]], appURL: URL) -> [[String: Any]] {
    let old = tiles.first { isOurTile($0, appURL: appURL) }
    let tile: [String: Any] = [
        "GUID": old?["GUID"] ?? UInt32.random(in: 1...UInt32.max),
        "tile-type": "file-tile",
        "tile-data": [
            "bundle-identifier": bundleID,
            "file-label": "墨译",
            "file-type": 41,
            "file-data": ["_CFURLString": appURL.absoluteString, "_CFURLStringType": 15]
        ]
    ]
    var result: [[String: Any]] = []
    var inserted = false
    for existing in tiles {
        if isOurTile(existing, appURL: appURL) {
            if !inserted { result.append(tile); inserted = true }
        } else { result.append(existing) }
    }
    if !inserted { result.append(tile) }
    return result
}

func makeAlias(to appURL: URL, at aliasURL: URL) throws {
    // Do not overwrite a same-named unrelated desktop file.
    if fm.fileExists(atPath: aliasURL.path) {
        let values = try aliasURL.resourceValues(forKeys: [.isAliasFileKey])
        guard values.isAliasFile == true,
              let resolved = try? URL(resolvingAliasFileAt: aliasURL, options: [.withoutUI]),
              resolved.standardizedFileURL == appURL.standardizedFileURL
                || Bundle(url: resolved)?.bundleIdentifier == bundleID else {
            try fail("桌面已有同名文件：\(aliasURL.path)。请先重命名该文件后重试。")
        }
    }
    let data = try appURL.bookmarkData(options: [.suitableForBookmarkFile],
                                     includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(data, to: aliasURL)
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { try fail("命令执行失败：\(executable)") }
}

func selfTest() throws {
    let app = URL(fileURLWithPath: "/Applications/MoTranslate.app")
    let other: [String: Any] = ["GUID": 123, "tile-type": "file-tile", "tile-data": ["file-label": "Keep me"]]
    let original: [[String: Any]] = [other]
    let once = updatedTiles(original, appURL: app)
    let twice = updatedTiles(once, appURL: app)
    guard once.count == 2, twice.count == 2,
          (twice.first as NSDictionary?)?.isEqual(to: other) == true,
          twice.filter({ isOurTile($0, appURL: app) }).count == 1 else {
        try fail("Dock 添加与重复部署测试失败")
    }
    let duplicate = updatedTiles([once[1], other, once[1]], appURL: app)
    guard duplicate.count == 2, duplicate.first?["GUID"] as? UInt32 == once[1]["GUID"] as? UInt32,
          duplicate[1]["GUID"] as? Int == 123 else { try fail("Dock 去重与位置保留测试失败") }
    let root = fm.temporaryDirectory.appendingPathComponent("MoTranslate-deploy-test-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let target = root.appendingPathComponent("Application with spaces.app")
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    let alias = root.appendingPathComponent("墨译.app")
    try makeAlias(to: target, at: alias)
    try makeAlias(to: target, at: alias)
    let resolved = try URL(resolvingAliasFileAt: alias, options: [.withoutUI])
    guard resolved.standardizedFileURL == target.standardizedFileURL else { try fail("桌面替身解析测试失败") }
    let unrelated = root.appendingPathComponent("unrelated.app")
    try Data("keep".utf8).write(to: unrelated)
    var rejected = false
    do { try makeAlias(to: target, at: unrelated) } catch { rejected = true }
    guard rejected, try Data(contentsOf: unrelated) == Data("keep".utf8) else { try fail("同名文件保护测试失败") }
    print("✓ Dock 保留、去重、重复部署和桌面替身测试通过")
}

func deploy(source: URL, destination: URL, backupRoot: URL, desktop: URL) throws {
    guard Bundle(url: source)?.bundleIdentifier == bundleID,
          fm.isExecutableFile(atPath: source.appendingPathComponent("Contents/MacOS/MoTranslate").path) else {
        try fail("构建产物无效，请先运行 ./build.sh release。")
    }
    if fm.fileExists(atPath: destination.path), Bundle(url: destination)?.bundleIdentifier != bundleID {
        try fail("安装目标已被其他应用占用：\(destination.path)")
    }
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createDirectory(at: desktop, withIntermediateDirectories: true)
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let backup = backupRoot.appendingPathComponent(stamp + "-" + String(UUID().uuidString.prefix(6)))
    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
    let domain = "com.apple.dock" as CFString
    let key = "persistent-apps" as CFString
    guard CFPreferencesAppSynchronize(domain) else { try fail("无法读取 Dock 偏好设置。") }
    let rawTiles = CFPreferencesCopyAppValue(key, domain)
    guard rawTiles == nil || rawTiles is [[String: Any]] else {
        try fail("Dock 配置格式无法识别，已停止以保护现有条目。")
    }
    let tiles = rawTiles as? [[String: Any]] ?? []
    let dockData = try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
    try dockData.write(to: backup.appendingPathComponent("Dock-persistent-apps.plist"), options: .atomic)
    let aliasURL = desktop.appendingPathComponent("墨译.app")
    // Check collision before installing or stopping the running application.
    if fm.fileExists(atPath: aliasURL.path) {
        let values = try aliasURL.resourceValues(forKeys: [.isAliasFileKey])
        guard values.isAliasFile == true,
              let resolved = try? URL(resolvingAliasFileAt: aliasURL, options: [.withoutUI]),
              resolved.standardizedFileURL == destination.standardizedFileURL
                || Bundle(url: resolved)?.bundleIdentifier == bundleID else {
            try fail("桌面已有同名文件：\(aliasURL.path)，请先重命名该文件。")
        }
        try fm.copyItem(at: aliasURL, to: backup.appendingPathComponent("Desktop-alias"))
    }
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".MoTranslate-stage-" + UUID().uuidString + ".app")
    try fm.copyItem(at: source, to: staging)
    defer { try? fm.removeItem(at: staging) }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    for app in running { app.terminate() }
    let deadline = Date().addingTimeInterval(5)
    while running.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard running.allSatisfy({ $0.isTerminated }) else {
        try fail("墨译仍在运行，请退出后重新部署；现有安装未改动。")
    }
    let previous = backup.appendingPathComponent("MoTranslate.zip")
    let existed = fm.fileExists(atPath: destination.path)
    if existed { try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", destination.path, previous.path]) }
    do {
        if existed { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
        try makeAlias(to: destination, at: aliasURL)
        let updated = updatedTiles(tiles, appURL: destination)
        CFPreferencesSetAppValue(key, updated as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else { try fail("Dock 设置写入失败。") }
        let saved = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
        guard saved.filter({ isOurTile($0, appURL: destination) }).count == 1 else {
            try fail("Dock 条目验证失败。")
        }
    } catch {
        try? fm.removeItem(at: destination)
        if existed { try? run("/usr/bin/ditto", ["-x", "-k", previous.path, destination.deletingLastPathComponent().path]) }
        if let aliasData = try? Data(contentsOf: backup.appendingPathComponent("Desktop-alias")) {
            try? aliasData.write(to: aliasURL, options: .atomic)
        } else { try? fm.removeItem(at: aliasURL) }
        CFPreferencesSetAppValue(key, rawTiles, domain)
        CFPreferencesAppSynchronize(domain)
        throw error
    }
    print("✓ 应用：\(destination.path)")
    print("✓ 桌面替身：\(aliasURL.path)")
    print("✓ Dock 已固定墨译，保留其他应用及排列")
    print("✓ 备份：\(backup.path)")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] { try selfTest() }
    else {
        guard arguments.count == 4 else { try fail("Usage: deploy.swift SOURCE_APP DESTINATION_APP BACKUP_DIR DESKTOP_DIR") }
        let paths = arguments.map { URL(fileURLWithPath: $0).standardizedFileURL }
        try deploy(source: paths[0], destination: paths[1], backupRoot: paths[2], desktop: paths[3])
    }
} catch {
    fputs("部署失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
