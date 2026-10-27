import Foundation

// File transfer (a144): a plain two-person chat between this phone and the PC, with no AI. What gw3-phone sends
// (tools/gw3_transfer.py public / page / library); the PC's messages sit on the left here, the phone's on the right.

/// One file of a message: links are the PC's signed /v1/media/… links (`url` the file itself, `thumb` a small
/// picture, `poster` a video's first frame), or demo: links in the demo.
struct TransferFile: Codable, Equatable, Hashable {
    var name: String
    var size: Int64
    var kind: String            // image | video | file
    var exists: Bool?
    var url: String?
    var thumb: String?
    var poster: String?

    var isMedia: Bool { kind == "image" || kind == "video" }
    /// still on the PC (a file deleted from the folder there has no links)
    var there: Bool { exists != false && !(url ?? "").isEmpty }
}

struct TransferMessage: Codable, Equatable, Identifiable {
    var id: String
    var ts: Double              // ms
    var from: String            // pc | phone
    var text: String
    var files: [TransferFile]
    var clientId: String?

    /// sent from this phone: on the right
    var mine: Bool { from == "phone" }
}

/// GET /v1/transfer: a page of messages, oldest first
struct TransferMessages: Codable, Equatable {
    var messages: [TransferMessage]
    var more: Bool
    var folder: String?         // where the files are on the PC (GupWorks Transfer in the home folder)
    var now: Double?            // the demo's recorded time
}

/// One file in the Library: a message's file with where it came from.
struct TransferItem: Codable, Equatable, Identifiable, Hashable {
    var id: String              // <message id>/<index>
    var messageId: String
    var ts: Double
    var from: String
    var name: String
    var size: Int64
    var kind: String
    var url: String?
    var thumb: String?
    var poster: String?

    var mine: Bool { from == "phone" }
    var isMedia: Bool { kind == "image" || kind == "video" }
    var file: TransferFile { TransferFile(name: name, size: size, kind: kind, exists: true, url: url, thumb: thumb, poster: poster) }
}

/// GET /v1/transfer/library: every file sent either way that's still on the PC, newest first
struct TransferLibraryList: Codable, Equatable {
    var items: [TransferItem]
    var folder: String?

    var media: [TransferItem] { items.filter(\.isMedia) }
    var files: [TransferItem] { items.filter { !$0.isMedia } }

    /// the Library of these messages (the demo's; the PC makes the real one from all of them)
    static func of(_ messages: [TransferMessage], folder: String?) -> TransferLibraryList {
        var items: [TransferItem] = []
        for m in messages {
            for (i, f) in m.files.enumerated() where f.there {
                items.append(TransferItem(id: "\(m.id)/\(i)", messageId: m.id, ts: m.ts, from: m.from, name: f.name,
                                          size: f.size, kind: f.kind, url: f.url, thumb: f.thumb, poster: f.poster))
            }
        }
        return TransferLibraryList(items: items.sorted { $0.ts > $1.ts }, folder: folder)
    }
}

/// An upload on the PC: how much of the file it has.
struct UploadState: Codable, Equatable {
    var id: String
    var received: Int64
    var size: Int64

    /// a 409's body: where the PC's copy stands
    struct Behind: Codable {
        var received: Int64
    }
}

struct UploadStart: Codable, Equatable {
    var name: String
    var size: Int64
    var type: String
}

/// POST /v1/transfer/messages: the words and the finished uploads; the same clientId again is the same message
struct TransferSend: Codable, Equatable {
    var text: String
    var files: [String]
    var clientId: String
}

enum TransferError: Error, Equatable {
    /// the upload isn't on the PC (anymore): it starts over
    case gone
    /// the PC's copy stands at this many bytes: go on from there
    case behind(Int64)
}

enum TransferKind {
    static let image: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

    /// image | video | file, by the name's extension (as the PC decides)
    static func of(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return image.contains(ext) ? "image" : video.contains(ext) ? "video" : "file"
    }

    /// a MIME type for the upload (the PC goes by the name)
    static func mime(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "gif": return "image/gif"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}

extension Format {
    /// 900 -> "900 B", 37_000 -> "36 KB", 5_000_000 -> "4.8 MB", 98_900_000 -> "94 MB": the desktop's sizeText
    /// (steps of 1024, one decimal under 10)
    static func bytes(_ n: Int64) -> String {
        if n < 1024 { return "\(max(0, n)) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var v = Double(n) / 1024, u = 0
        while v >= 1024 && u < 3 {
            v /= 1024
            u += 1
        }
        return (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)) + " " + units[u]
    }

    /// "Today 9:41 PM", "Yesterday 8:02 AM", "Mon 3:15 PM", "Oct 18, 3:15 PM": the transfer chat's time lines
    static func dayTime(_ ms: Double, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        var clock = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        let t = date.formatted(clock)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(t)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "Yesterday \(t)"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        var day = days < 7 && days > 0 ? Date.FormatStyle().weekday(.abbreviated) : Date.FormatStyle().month(.abbreviated).day()
        day = day.locale(locale)
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        return "\(date.formatted(day)) \(t)"
    }
}

/// How the chat lays its messages out: a time line before the first and after a gap or a new day; a little room
/// between one side's messages, more where the side changes (the desktop's TransferChat does the same).
enum TransferLayout {
    static let gap: Double = 30 * 60 * 1000

    /// the messages that get a time line above them
    static func timeLines(_ messages: [TransferMessage], calendar: Calendar = .current) -> Set<String> {
        var out: Set<String> = []
        var last: Double?
        for m in messages {
            if let l = last {
                let a = Date(timeIntervalSince1970: l / 1000), b = Date(timeIntervalSince1970: m.ts / 1000)
                if m.ts - l > gap || !calendar.isDate(a, inSameDayAs: b) { out.insert(m.id) }
            } else {
                out.insert(m.id)
            }
            last = m.ts
        }
        return out
    }

    /// the room above a message: 4 pt under the same side, 14 where the side changes
    static func spacing(_ m: TransferMessage, after prev: TransferMessage?) -> Double {
        guard let prev else { return 0 }
        return prev.mine == m.mine ? 4 : 14
    }
}
