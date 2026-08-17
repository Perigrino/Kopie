import Foundation
import KopieCore
import AppKit

enum SelfTest {
    static func run(_ args: [String]) -> Bool {
        guard let first = args.first else { return false }
        let store = ClipStore()
        let writer = DiskClipWriter()
        let pipe = CapturePipeline(store: store, writer: writer)
        let cfg = CaptureConfig(paused: false)   // smoke always captures
        // ensure storage dir is isolated via KOPIE_STORAGE_DIR (set by caller)
        switch first {
        case "--smoke-capture":
            let text = args.count > 1 ? args[1] : "smoke"
            let r = pipe.process(.init(kind: .text(text), sourceAppID: nil), config: cfg)
            if case .captured(let id) = r { print("ID \(id)") } else { print("RESULT \(r)") }
        case "--smoke-capture-image":
            guard args.count > 1, let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])) else { print("ERR no image"); return true }
            let r = pipe.process(.init(kind: .image(data), sourceAppID: nil), config: cfg)
            if case .captured(let id) = r { print("ID \(id)") } else { print("RESULT \(r)") }
        case "--smoke-restore":
            guard args.count > 1, let id = Int64(args[1]) else { print("ERR id"); return true }
            if let item = store.get(id) {
                let svc = RestoreService(); svc.restore(item, writer: writer); print("RESTORED \(item.kind.rawValue)")
            } else { print("ERR notfound") }
        case "--smoke-list":
            for it in store.query(.init(limit: 50)) {
                print("\(it.id) \(it.kind.rawValue) \(it.createdAt.timeIntervalSince1970) \(it.preview)")
            }
        case "--smoke-count":
            print("COUNT \(store.count())")
        case "--smoke-purge":
            let days = args.count > 1 ? Double(args[1]) ?? 7 : 7
            let delFav = (args.count > 2 && args[2] == "fav")
            let p = RetentionJob(store: store)
            let n = p.run(config: .init(period: RetentionPeriod(rawValue: Int(days)) ?? .daySeven, deleteFavorites: delFav))
            print("PURGED \(n) remaining \(store.count())")
        case "--smoke-readboard":
            let b = NSPasteboard.general
            if let s = b.string(forType: .string) { print("TEXT \(s)") }
            print("TYPES \(b.types?.map { "\($0)" } ?? [])")
        default:
            return false
        }
        return true
    }
}
