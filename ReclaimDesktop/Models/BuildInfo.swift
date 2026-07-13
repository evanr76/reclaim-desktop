import Foundation
import MachO

/// Per-build identity: the main executable's Mach-O UUID (unique per build) plus
/// the binary's build timestamp. Read at runtime — no build script required.
public enum BuildInfo {
    /// LC_UUID of the main executable.
    public static let uuid: UUID? = {
        for i in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(i) else { continue }
            guard header.pointee.filetype == UInt32(MH_EXECUTE) else { continue }
            var ptr = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<header.pointee.ncmds {
                let lc = ptr.loadUnaligned(as: load_command.self)
                if lc.cmd == UInt32(LC_UUID) {
                    return UUID(uuid: ptr.loadUnaligned(as: uuid_command.self).uuid)
                }
                ptr = ptr.advanced(by: Int(lc.cmdsize))
            }
        }
        return nil
    }()

    public static var shortUUID: String {
        uuid.map { String($0.uuidString.prefix(8)).lowercased() } ?? "unknown"
    }

    public static var buildDate: Date? {
        guard let path = Bundle.main.executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// e.g. "v1.0 · a1b2c3d4 · 2026-07-13 09:15"
    public static var label: String {
        let ts: String
        if let date = buildDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            ts = f.string(from: date)
        } else {
            ts = "—"
        }
        return "v\(version) · \(shortUUID) · \(ts)"
    }
}
