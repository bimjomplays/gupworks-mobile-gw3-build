import Foundation

// The Studio's Edit stage as the PC sends it: tools/gw3_studio_edit.py's timeline model (one list of clips a
// track, absolute starts and lengths in seconds) and gw3_studio_sound.py's library, mix and mixdown, through
// gw3-phone's /v1/studio/<route> (tools/gw3_phone_studio.py), which adds signed links to the media.

/// a clip's tie to a voice line: the PC keeps the clip on its line when the voice changes
struct StudioAnchor: Codable, Equatable {
    var line: String?
    var edge: String?
    var offset: Double?
    var at: Double?
}

/// One clip on a track; which fields mean something depends on the track (editModel.ts Clip).
struct StudioClip: Codable, Equatable, Identifiable {
    var id: String
    var start: Double
    var dur: Double
    var label: String?
    var anchor: StudioAnchor?
    // video
    var media: String?
    var shot: String?
    var trim: Double?
    var kenburns: String?       // in | out | left | right
    var kbZoom: Double?         // how far Ken Burns zooms (1.02-2, 1.15 when nil)
    var transition: String?     // cut | crossfade | dip (into this clip from the one before)
    var fade: Double?
    // overlay
    var text: String?
    var style: String?          // title | lower | caption
    // music, sfx
    var file: String?
    var gain: Double?
    var fadeIn: Double?
    var fadeOut: Double?
    var duck: Bool?

    var end: Double { start + dur }
}

enum StudioTrack: String, CaseIterable, Codable {
    case video, overlay, music, sfx
}

struct StudioModel: Codable, Equatable {
    var video: [StudioClip] = []
    var overlay: [StudioClip] = []
    var music: [StudioClip] = []
    var sfx: [StudioClip] = []

    init(video: [StudioClip] = [], overlay: [StudioClip] = [], music: [StudioClip] = [], sfx: [StudioClip] = []) {
        (self.video, self.overlay, self.music, self.sfx) = (video, overlay, music, sfx)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = try c.decodeIfPresent([StudioClip].self, forKey: .video) ?? []
        overlay = try c.decodeIfPresent([StudioClip].self, forKey: .overlay) ?? []
        music = try c.decodeIfPresent([StudioClip].self, forKey: .music) ?? []
        sfx = try c.decodeIfPresent([StudioClip].self, forKey: .sfx) ?? []
    }

    subscript(t: StudioTrack) -> [StudioClip] {
        get {
            switch t {
            case .video: return video
            case .overlay: return overlay
            case .music: return music
            case .sfx: return sfx
            }
        }
        set {
            switch t {
            case .video: video = newValue
            case .overlay: overlay = newValue
            case .music: music = newValue
            case .sfx: sfx = newValue
            }
        }
    }
}

struct StudioEditWord: Codable, Equatable {
    var w: String
    var t: Double
    var end: Double
}

/// A line of the voice track; its words' times count from the line's start.
struct StudioVoiceLine: Codable, Equatable, Identifiable {
    var id: String
    var chapter: Int
    var text: String
    var start: Double
    var end: Double
    var file: String?
    var words: [StudioEditWord]
}

/// A shot-list entry; `src` is its render or draft (`from` says which).
struct StudioShot: Codable, Equatable, Identifiable {
    var id: String
    var chapter: Int?
    var lines: [String]
    var start: Double
    var end: Double
    var style: String
    var description: String
    var status: String
    var src: String?
    var from: String?
}

/// A research photo or clip with its rights (cleared: public domain, or CC with credit).
struct StudioPhoto: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var file: String
    var kind: String
    var rights: String
    var credit: String
    var cleared: Bool
    var rejected: Bool
}

struct StudioEditChapter: Codable, Equatable {
    var chapter: Int
    var title: String
    var start: Double
    var end: Double
}

/// The shared undo history's next steps (stage, phone and chat): their labels and who made them.
struct StudioHistory: Codable, Equatable {
    var undo: String?
    var undoBy: String?
    var redo: String?
    var redoBy: String?
    var n: Int?
}

/// A file of the video folder as the phone loads it: a signed link to a small copy (a 640 px video, a JPEG, an
/// AAC sound), a thumbnail (a strip of frames for videos), a sound's outline, and a key that changes with the file.
struct StudioMedia: Codable, Equatable {
    var url: String
    var kind: String            // video | image | audio
    var thumb: String?
    var peaks: String?
    var seconds: Double?
    var key: String?
    var frames: Int?            // pictures in a video's thumb strip
}

struct StudioTrackGain: Codable, Equatable {
    var gain: Double
}

struct StudioDuck: Codable, Equatable {
    var on: Bool
    var depth: Double
    var attack: Double
    var release: Double
    var hold: Double
}

/// one voice line's own volume and fades (mix.lines)
struct StudioLineMix: Codable, Equatable {
    var gain: Double?
    var fadeIn: Double?
    var fadeOut: Double?
}

/// The mix settings in timeline.json's studio.mix (gw3_studio_sound.norm_mix): gains are linear (0-2).
struct StudioMix: Codable, Equatable {
    var voice = StudioTrackGain(gain: 1)
    var music = StudioTrackGain(gain: 1)
    var sfx = StudioTrackGain(gain: 1)
    var duck = StudioDuck(on: true, depth: 12, attack: 0.25, release: 0.6, hold: 0.5)
    var target: Double = -14
    var lines: [String: StudioLineMix]?

    func gain(_ t: StudioTrack) -> Double {
        t == .music ? music.gain : t == .sfx ? sfx.gain : voice.gain
    }
}

struct StudioLoudness: Codable, Equatable {
    var I: Double?
    var TP: Double?
    var LRA: Double?
}

/// studio/sound/mix.json: the last mixdown's measurements
struct StudioMixdown: Codable, Equatable {
    var file: String
    var target: Double
    var lufs: Double?
    var truePeak: Double?
    var lra: Double?
    var gain: Double?
    var before: StudioLoudness?
    var seconds: Double?
    var at: Double?
}

/// a sound brought in (sound/sounds.json) with the clips that use it
struct StudioSound: Codable, Equatable, Identifiable {
    var file: String
    var source: String?
    var title: String?
    var author: String?
    var url: String?
    var licence: String?
    var seconds: Double?
    var credits: Double?
    var prompt: String?
    var clips: [String]?
    var missing: Bool?
    var id: String { file }
}

/// a generation or mixdown running on the PC
struct StudioEditJob: Codable, Equatable, Identifiable {
    var id: String
    var kind: String            // sfx | music | mixdown
    var status: String          // running | done | failed
    var progress: Double?
    var phase: String?
    var file: String?
    var error: String?
    var prompt: String?
    var estimate: Double?
    var cost: Double?
    var report: StudioMixdown?
}

struct StudioCredits: Codable, Equatable {
    var left: Double?
    var limit: Double?
    var used: Double?
}

struct StudioRates: Codable, Equatable {
    var sfx: Double?
    var music: Double?
}

/// The Edit stage's view: studio/sound (the timeline, the library, the mix) with the bridge's media links.
struct StudioEditView: Codable, Equatable {
    var title: String
    var kind: String?
    var readonly: Bool
    var reason: String?
    var exists: Bool?
    var fps: Double?
    var size: [Double]?
    var model: StudioModel
    var duration: Double
    var voice: [StudioVoiceLine]
    var shots: [StudioShot]
    var photos: [StudioPhoto]
    var audio: [String]?
    var by: String?
    var version: String
    var base: String?           // the timeline's own version, which saves are made over
    var history: StudioHistory?
    var chatId: String?
    var chapters: [StudioEditChapter]?
    // the sound part
    var mix: StudioMix?
    var log: [StudioSound]?
    var jobs: [StudioEditJob]?
    var mixdown: StudioMixdown?
    var mixCurrent: Bool?
    var credits: StudioCredits?
    var rates: StudioRates?
    var media: [String: StudioMedia]?

    /// the version saves are made over
    var timelineVersion: String { base ?? version }

    /// The view after a save's or an undo's answer: the timeline part from it, the rest kept until the next load.
    func merged(_ new: StudioEditView) -> StudioEditView {
        var v = new
        v.mix = new.mix ?? mix
        v.log = new.log ?? log
        v.jobs = new.jobs ?? jobs
        v.mixdown = new.mixdown ?? mixdown
        v.mixCurrent = new.mixCurrent ?? (new.model == model ? mixCurrent : false)
        v.credits = new.credits ?? credits
        v.rates = new.rates ?? rates
        var media = self.media ?? [:]
        for (k, x) in new.media ?? [:] { media[k] = x }
        v.media = media
        if new.mix == nil { v.base = nil }  // an edit view: its version is the timeline's
        return v
    }

    var shotsById: [String: StudioShot] { Dictionary(shots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
}

// MARK: answers

struct StudioUndoReply: Decodable {
    var view: StudioEditView
    var label: String?
    init(from decoder: Decoder) throws {
        view = try StudioEditView(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        label = try c.decodeIfPresent(String.self, forKey: .undone) ?? c.decodeIfPresent(String.self, forKey: .redone)
    }
    enum Keys: String, CodingKey { case undone, redone }
}

/// a poll's answer: nothing changed since `known`, or the whole view
struct StudioPoll: Decodable {
    var unchanged: Bool
    var view: StudioEditView?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        unchanged = try c.decodeIfPresent(Bool.self, forKey: .unchanged) ?? false
        view = unchanged ? nil : try StudioEditView(from: decoder)
    }
    enum Keys: String, CodingKey { case unchanged }
}

struct StudioFound: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var author: String?
    var seconds: Double?
    var preview: String?
    var page: String?
    var licence: String?
    var about: String?
    var tags: [String]?
}

struct StudioSearchReply: Codable, Equatable {
    var query: String
    var page: Int
    var results: [StudioFound]
    var more: Bool
}

struct StudioGetReply: Codable, Equatable {
    var file: String
    var sound: StudioSound?
    var media: [String: StudioMedia]?
}

/// An ElevenLabs generation's estimate (no confirm), or the job it started (confirm).
struct StudioGenerateReply: Codable, Equatable {
    var estimate: Double
    var rate: Double?
    var how: String?
    var seconds: Double
    var left: Double?
    var job: StudioEditJob?
}

struct StudioJobReply: Codable, Equatable {
    var job: StudioEditJob
}

struct StudioVideoRecord: Codable, Equatable {
    var id: String
    var chatId: String?
}

// MARK: requests

/// which video a call is about
struct StudioRef: Codable, Equatable, Hashable {
    var projectId: String
    var videoId: String
}

/// A request body: the video's ids plus the call's own fields, flat in one JSON object.
struct StudioBody<X: Encodable>: Encodable {
    var ref: StudioRef
    var x: X
    func encode(to encoder: Encoder) throws {
        try ref.encode(to: encoder)
        try x.encode(to: encoder)
    }
}

struct NoFields: Codable {}

struct StudioSaveBody: Codable {
    var model: StudioModel
    var base: String
    var label: String
}

struct StudioMixBody: Codable {
    var mix: StudioMix
    var base: String
    var label: String
}

struct StudioKnown: Codable {
    var known: String?
}

struct StudioSearchBody: Codable {
    var q: String
    var page: Int
}

struct StudioIdBody: Codable {
    var id: String
}

struct StudioGenerateBody: Codable, Equatable {
    var kind: String
    var prompt: String
    var seconds: Double
    var confirm: Bool
}

struct StudioAddBody: Codable {
    var file: String
    var title: String
}

struct StudioOpenBody: Codable {
    var stage: String
}

struct StudioSelection: Codable, Equatable {
    var stage: String
    var kind: String
    var id: String
    var label: String
}

struct StudioSelectBody: Encodable {
    var selection: StudioSelection?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(selection, forKey: .selection)  // null clears it
    }
    enum Keys: String, CodingKey { case selection }
}

extension APIClient {
    /// a /v1/studio route with the video's ids and the call's fields
    func studio<T: Decodable, X: Encodable>(_ p: Pairing, _ ref: StudioRef, _ route: String, _ x: X,
                                            slow: Bool = false) async throws -> T {
        try await studioCall(p, route, StudioBody(ref: ref, x: x), slow: slow)
    }

    func studioEdit(_ p: Pairing, _ ref: StudioRef, known: String?) async throws -> StudioPoll {
        try await studio(p, ref, "sound", StudioKnown(known: known), slow: true)
    }

    func studioSave(_ p: Pairing, _ ref: StudioRef, _ b: StudioSaveBody) async throws -> StudioEditView {
        try await studio(p, ref, "edit/save", b)
    }

    func studioUndo(_ p: Pairing, _ ref: StudioRef, back: Bool) async throws -> StudioUndoReply {
        try await studio(p, ref, back ? "edit/undo" : "edit/redo", NoFields(), slow: true)
    }

    func studioMix(_ p: Pairing, _ ref: StudioRef, _ b: StudioMixBody) async throws -> StudioEditView {
        try await studio(p, ref, "sound/mix", b, slow: true)
    }

    func studioSearch(_ p: Pairing, _ ref: StudioRef, _ q: String, page: Int = 1) async throws -> StudioSearchReply {
        try await studio(p, ref, "sound/search", StudioSearchBody(q: q, page: page), slow: true)
    }

    func studioGet(_ p: Pairing, _ ref: StudioRef, id: String) async throws -> StudioGetReply {
        try await studio(p, ref, "sound/get", StudioIdBody(id: id), slow: true)
    }

    func studioGenerate(_ p: Pairing, _ ref: StudioRef, _ b: StudioGenerateBody) async throws -> StudioGenerateReply {
        try await studio(p, ref, "sound/generate", b, slow: true)
    }

    func studioAddSound(_ p: Pairing, _ ref: StudioRef, _ b: StudioAddBody) async throws -> StudioGetReply {
        try await studio(p, ref, "sound/add", b, slow: true)
    }

    func studioMixdown(_ p: Pairing, _ ref: StudioRef) async throws -> StudioJobReply {
        try await studio(p, ref, "sound/mixdown", NoFields())
    }

    func studioOpen(_ p: Pairing, _ ref: StudioRef, stage: String) async throws -> StudioVideoRecord {
        try await studio(p, ref, "video/open", StudioOpenBody(stage: stage))
    }

    func studioSelect(_ p: Pairing, _ ref: StudioRef, _ s: StudioSelection?) async throws -> OKish {
        try await studio(p, ref, "video/select", StudioSelectBody(selection: s))
    }
}

/// any JSON answer, when only that it came matters
struct OKish: Decodable {
    init(from decoder: Decoder) throws {}
}
