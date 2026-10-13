import Foundation

enum FrameRate: String, CaseIterable, Codable, Identifiable {
    case fps23976, fps24, fps25, fps2997df, fps2997ndf, fps30, fps50, fps5994df, fps5994ndf, fps60

    var id: String { rawValue }

    /// Nominal frames per second used for timecode counting.
    var timebase: Int {
        switch self {
        case .fps23976, .fps24: 24
        case .fps25: 25
        case .fps2997df, .fps2997ndf, .fps30: 30
        case .fps50: 50
        case .fps5994df, .fps5994ndf, .fps60: 60
        }
    }

    var isNTSC: Bool {
        switch self {
        case .fps23976, .fps2997df, .fps2997ndf, .fps5994df, .fps5994ndf: true
        default: false
        }
    }

    var isDropFrame: Bool { self == .fps2997df || self == .fps5994df }

    /// Real frames per second.
    var fps: Double { isNTSC ? Double(timebase) * 1000 / 1001 : Double(timebase) }

    var label: String {
        switch self {
        case .fps23976: "23.976"
        case .fps24: "24"
        case .fps25: "25"
        case .fps2997df: "29.97 DF"
        case .fps2997ndf: "29.97 NDF"
        case .fps30: "30"
        case .fps50: "50"
        case .fps5994df: "59.94 DF"
        case .fps5994ndf: "59.94 NDF"
        case .fps60: "60"
        }
    }

    static func matching(timebase: Int, ntsc: Bool, dropFrame: Bool) -> FrameRate? {
        allCases.first { $0.timebase == timebase && $0.isNTSC == ntsc && $0.isDropFrame == (dropFrame && ntsc) }
    }
}

struct Timecode: Codable, Hashable, Comparable {
    var hours = 0
    var minutes = 0
    var seconds = 0
    var frames = 0
    var dropFrame = false

    init(hours: Int, minutes: Int, seconds: Int, frames: Int, dropFrame: Bool = false) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.dropFrame = dropFrame
    }

    /// Builds a timecode from a frame count since 00:00:00:00, wrapping at 24 hours.
    init(frameCount: Int, rate: FrameRate) {
        let tb = rate.timebase
        var count = frameCount
        if rate.isDropFrame {
            let drop = tb / 15
            let per10Min = tb * 600 - drop * 9
            let perMin = tb * 60 - drop
            let day = per10Min * 144
            count = ((count % day) + day) % day
            let tens = count / per10Min
            let rem = count % per10Min
            count += drop * 9 * tens + (rem > drop ? drop * ((rem - drop) / perMin) : 0)
        } else {
            let day = tb * 86400
            count = ((count % day) + day) % day
        }
        frames = count % tb
        seconds = count / tb % 60
        minutes = count / (tb * 60) % 60
        hours = count / (tb * 3600) % 24
        dropFrame = rate.isDropFrame
    }

    /// Time-of-day timecode. Non-drop rates follow the wall clock second for second;
    /// drop-frame rates count real frames since midnight.
    init(secondsSinceMidnight: Double, rate: FrameRate) {
        if rate.isDropFrame {
            self.init(frameCount: Int(secondsSinceMidnight * rate.fps), rate: rate)
        } else {
            let whole = Int(secondsSinceMidnight)
            let frame = min(Int((secondsSinceMidnight - Double(whole)) * Double(rate.timebase)), rate.timebase - 1)
            self.init(hours: whole / 3600 % 24, minutes: whole / 60 % 60, seconds: whole % 60, frames: frame)
        }
    }

    init?(string: String, rate: FrameRate) {
        let parts = string.split(whereSeparator: { ":;.".contains($0) }).compactMap { Int($0) }
        guard parts.count == 4, parts[0] < 24, parts[1] < 60, parts[2] < 60, parts[3] < rate.timebase else { return nil }
        self.init(hours: parts[0], minutes: parts[1], seconds: parts[2], frames: parts[3], dropFrame: rate.isDropFrame)
    }

    var string: String {
        String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, dropFrame ? ";" : ":", frames)
    }

    func frameCount(rate: FrameRate) -> Int {
        let tb = rate.timebase
        let totalMinutes = hours * 60 + minutes
        var count = (totalMinutes * 60 + seconds) * tb + min(frames, tb - 1)
        if rate.isDropFrame {
            count -= (tb / 15) * (totalMinutes - totalMinutes / 10)
        }
        return count
    }

    static func < (a: Timecode, b: Timecode) -> Bool {
        (a.hours, a.minutes, a.seconds, a.frames) < (b.hours, b.minutes, b.seconds, b.frames)
    }
}
