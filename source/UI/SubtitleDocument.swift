import Foundation
import AppKit

struct SubtitleWord: Codable, Equatable { var text: String; var start: Double; var end: Double }
struct SubtitleCue: Codable, Equatable {
    var id: String = UUID().uuidString
    var start: Double
    var end: Double
    var text: String
    var words: [SubtitleWord] = []
    init(start: Double, end: Double, text: String, words: [SubtitleWord] = []) {
        self.start = start; self.end = end; self.text = text; self.words = words
    }
    enum CodingKeys: String, CodingKey { case id, start, end, text, words }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        start = try c.decode(Double.self, forKey: .start); end = try c.decode(Double.self, forKey: .end)
        text = try c.decode(String.self, forKey: .text); words = try c.decodeIfPresent([SubtitleWord].self, forKey: .words) ?? []
    }
}
struct SubtitleStyle: Codable, Equatable {
    static let preferredFontName: String = {
        // Variable and static font installations can expose different PostScript names.
        let faces=NSFontManager.shared.availableMembers(ofFontFamily:"Delight") ?? []
        return faces.first(where:{ ($0[1] as? String)=="Semi Bold" })?.first as? String ?? "Delight-SemiBold"
    }()
    var fontName = SubtitleStyle.preferredFontName
    var fontFamily = "Delight"
    var fontFace = "Semi Bold"
    var outlineColor = "#000000"
    var positionX = 0.5
    var positionY = 0.88
    var fontSize: Double = 70
    var color = "#FFFFFF"
    var outline: Double = 0
    var bottomMargin: Double = 70
    var top = false
    var bold = false
}
struct SubtitleProject: Codable, Equatable {
    var version = 1
    var canvas:SubtitleCanvas?
    var videoPath: String = ""
    var duration: Double = 0
    var segments: [SubtitleCue] = []
    var style = SubtitleStyle()
    var lines = 1
    var maxChars = 35
    var maxDuration: Double = 3
    var context = ""
    var timelineOffset: Double = 0
    var model = "Whisper large-v3"
    var exportSegments: [SubtitleCue] { segments.map { cue in var result = cue; result.start += timelineOffset; result.end += timelineOffset; return result } }
    func validated() throws -> SubtitleProject {
        guard timelineOffset.isFinite, timelineOffset >= 0, timelineOffset < 864_000, version == 1, duration.isFinite, duration >= 0,
              [1,2].contains(lines), (20...80).contains(maxChars), (1...20).contains(maxDuration),
              style.fontSize.isFinite, (12...160).contains(style.fontSize),
              style.positionX.isFinite, (0...1).contains(style.positionX),
              style.positionY.isFinite, (0...1).contains(style.positionY),
              style.outlineColor.range(of: "^#[0-9a-fA-F]{6}$",options:.regularExpression) != nil,
              style.outline.isFinite, (0...10).contains(style.outline),
              style.bottomMargin.isFinite, (0...400).contains(style.bottomMargin),
              style.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              segments.count <= 100_000 else { throw SubtitleError.invalid("Le projet contient des paramètres invalides.") }
        guard canvas?.isValid != false else {throw SubtitleError.invalid("Format de séquence invalide.")}
        try SubtitleFormat.validate(segments)
        return self
    }
}
struct TranscriptionResult: Decodable {
    var segments: [SubtitleCue]
    var duration: Double?
    var model: String?
}
enum SubtitleError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
enum SubtitleFormat {
    static func validate(_ cues: [SubtitleCue]) throws {
        var previous: Double = 0
        for (index, cue) in cues.enumerated() {
            guard cue.start.isFinite, cue.end.isFinite, cue.start >= 0, cue.end > cue.start,
                  cue.start >= previous - 0.0001, cue.end < 864_000,
                  !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SubtitleError.invalid("Le sous-titre \(index + 1) a un texte vide, un temps invalide ou chevauche le précédent.")
            }
            previous = cue.end
        }
    }
    static func timestamp(_ value: Double, separator: String = ",") -> String {
        let ms = max(0, Int((value * 1000).rounded()))
        return String(format: "%02d:%02d:%02d%@%03d", ms/3_600_000, (ms/60_000)%60, (ms/1000)%60, separator, ms%1000)
    }
    static func parseTime(_ input: String) -> Double? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let seconds = Double(parts.last!), seconds.isFinite, seconds >= 0 else { return nil }
        if parts.count == 1 { return seconds }
        guard seconds < 60, let minutes = Double(parts[parts.count - 2]), minutes >= 0, minutes.rounded() == minutes else { return nil }
        if parts.count == 2 { return minutes * 60 + seconds }
        guard minutes < 60, let hours = Double(parts[0]), hours >= 0, hours.rounded() == hours else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
    static func srt(_ cues: [SubtitleCue]) throws -> String {
        try validate(cues)
        return cues.enumerated().map { "\($0.offset + 1)\n\(timestamp($0.element.start)) --> \(timestamp($0.element.end))\n\($0.element.text)\n" }.joined(separator: "\n")
    }
    static func vtt(_ cues: [SubtitleCue]) throws -> String {
        try validate(cues)
        // Escape WebVTT markup while keeping the author's literal words.
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        return "WEBVTT\n\n" + cues.enumerated().map { "\($0.offset + 1)\n\(timestamp($0.element.start, separator: ".")) --> \(timestamp($0.element.end, separator: "."))\n\(escaped($0.element.text))\n" }.joined(separator: "\n")
    }
    static func ass(_ cues: [SubtitleCue], style: SubtitleStyle, canvas:SubtitleCanvas = .fullHD, lines:Int=2) throws -> String {
        try validate(cues)
        guard canvas.isValid else {throw SubtitleError.invalid("Format ASS invalide.")}
        func time(_ t: Double) -> String {
            let cs = Int((t*100).rounded()); return String(format: "%d:%02d:%02d.%02d", cs/360000, (cs/6000)%60, (cs/100)%60, cs%100)
        }
        let hex = style.color.dropFirst(); let r = hex.prefix(2); let g = hex.dropFirst(2).prefix(2); let b = hex.suffix(2)
        let stroke = style.outlineColor.dropFirst();let sr=stroke.prefix(2),sg=stroke.dropFirst(2).prefix(2),sb=stroke.suffix(2)
        let safeFont = style.fontName.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
        var result = """
        [Script Info]
        Title: Sous-titres FilmCraft
        ScriptType: v4.00+
        PlayResX: \(Int(canvas.width))
        PlayResY: \(Int(canvas.height))
        WrapStyle: 2
        ScaledBorderAndShadow: yes

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,\(safeFont),\(style.fontSize*canvas.scale),&H00\(b)\(g)\(r),&H000000FF,&H00\(sb)\(sg)\(sr),&H80000000,\(style.bold ? -1 : 0),0,0,0,100,100,0,0,1,\(style.outline*canvas.scale),0,\(style.top ? 8 : 2),80,80,\(Int(style.bottomMargin)),1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        for cue in cues {
            // ASS braces and backslashes are control syntax, not literal author text.
            let layout=SubtitleTextLayout.make(text:cue.text,style:style,canvas:canvas,lines:lines)
            let text=layout.text.replacingOccurrences(of:"\\",with:"＼").replacingOccurrences(of:"{",with:"｛").replacingOccurrences(of:"}",with:"｝").replacingOccurrences(of:"\n",with:"\\N")
            let x=Int(layout.frame.midX.rounded()),y=Int(layout.frame.midY.rounded())
            result += "Dialogue: 0,\(time(cue.start)),\(time(cue.end)),Default,,0,0,0,,{\\an5\\pos(\(x),\(y))\\fs\(String(format:"%.3f",layout.fontSize))}\(text)\n"
        }
        return result
    }
    static func importSRT(_ raw: String) throws -> [SubtitleCue] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        let regex = try NSRegularExpression(pattern: "(?m)^\\s*\\n")
        let range = NSRange(normalized.startIndex..., in: normalized)
        let blocks = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "\u{001F}").split(separator: "\u{001F}")
        var result: [SubtitleCue] = []
        for block in blocks {
            var lines = block.components(separatedBy: "\n")
            while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeFirst() }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }), timingIndex <= 1 else { throw SubtitleError.invalid("Le fichier SRT contient un bloc sans repères temporels.") }
            let times = lines[timingIndex].components(separatedBy: "-->")
            guard times.count == 2, let start = parseTime(times[0]), let end = parseTime(times[1]) else { throw SubtitleError.invalid("Le fichier SRT contient un temps illisible.") }
            let text = lines.dropFirst(timingIndex+1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(SubtitleCue(start: start, end: end, text: text))
        }
        guard !result.isEmpty else { throw SubtitleError.invalid("Aucun sous-titre dans ce fichier.") }
        try validate(result); return result
    }
    // Edited/imported cues are timed proportionally to their word lengths. Reflow
    // preserves every word and both interval endpoints; no word timing is invented.
    // An indivisible word can exceed the line length or its allocated duration.
    static func reflow(_ cues: [SubtitleCue], lines: Int, maxChars: Int, maxDuration: Double) -> [SubtitleCue] {
        var result: [SubtitleCue] = []
        let lineLimit = max(1, lines), charLimit = max(1, maxChars)
        let durationLimit = max(0.001, maxDuration)
        func wrapped(_ tokens: [String]) -> [String] {
            var rows: [String] = []; var row = ""
            for token in tokens {
                if !row.isEmpty && row.count + 1 + token.count > charLimit {
                    rows.append(row); row = token
                } else { row += (row.isEmpty ? "" : " ") + token }
            }
            if !row.isEmpty { rows.append(row) }
            return rows
        }
        for cue in cues {
            let tokens = cue.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !tokens.isEmpty else { continue }
            let totalWeight = max(1, tokens.reduce(0) { $0 + $1.count })
            let durationPerWeight = (cue.end - cue.start) / Double(totalWeight)
            var chunks: [String] = []; var group: [String] = []; var weight = 0
            for token in tokens {
                let candidate = group + [token]
                let exceedsLines = wrapped(candidate).count > lineLimit
                let exceedsDuration = Double(weight + token.count) * durationPerWeight > durationLimit + 0.000_001
                if !group.isEmpty && (exceedsLines || exceedsDuration) {
                    chunks.append(wrapped(group).joined(separator: "\n"))
                    group = [token]; weight = token.count
                } else { group = candidate; weight += token.count }
            }
            if !group.isEmpty { chunks.append(wrapped(group).joined(separator: "\n")) }
            appendTimed(chunks, cue: cue, to: &result)
        }
        return result
    }

    private static func appendTimed(_ chunks: [String], cue: SubtitleCue, to result: inout [SubtitleCue]) {
        func weight(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).reduce(0) { $0 + $1.count } }
        let total = max(1, chunks.reduce(0) { $0 + weight($1) }); var done = 0
        for (i, text) in chunks.enumerated() {
            let start = cue.start + (cue.end-cue.start) * Double(done) / Double(total)
            done += weight(text)
            let end = i == chunks.count-1 ? cue.end : cue.start + (cue.end-cue.start) * Double(done) / Double(total)
            result.append(SubtitleCue(start: start, end: end, text: text))
        }
    }
}

#if FILMCRAFT_INTEGRATION
enum SubtitleFilmCraftAdapter {
    static func graphicProperties(_ style: SubtitleStyle, canvas:SubtitleCanvas) -> [String:Any] {
        ["align":"center", "fill_color":style.color, "stroke":style.outline>0,
         "stroke_type":"Outer", "stroke_width":style.outline*canvas.scale,
         "stroke_color":style.outlineColor, "faux_bold":false]
    }
    static func style(_ source: SubtitleStyle) -> FilmCraftCaptionStyle {
        var target = FilmCraftCaptionStyle()
        target.font = source.fontName; target.size = source.fontSize
        target.color = source.color; target.outline = source.outline;target.outlineColor=source.outlineColor
        target.anchor = source.top ? "top" : "bottom"
        // FilmCraft stores safe margins as a fraction of frame height.
        target.margin = source.bottomMargin / 1080
        target.background = false
        return target
    }
}
#endif
