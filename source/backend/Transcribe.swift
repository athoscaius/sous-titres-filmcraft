import Foundation
import AVFoundation
import CoreMedia
import Darwin

struct EngineError: LocalizedError { var message: String; var errorDescription: String? { message } }
struct Word: Codable { var text: String; var start: Double; var end: Double }
struct Cue: Codable { var id = UUID().uuidString; var start: Double; var end: Double; var text: String; var words: [Word] }
struct Transcript: Codable { var version = 1; var language = "fr"; var source: String; var duration: Double; var model = "Whisper large-v3 Q5_0"; var segments: [Cue] }
var childPID: Int32 = 0
var cancelled: Int32 = 0
func cancelHandler(_ sig: Int32) { cancelled = 1; if childPID > 0 { kill(childPID, SIGTERM) } }
func checkCancelled() throws { if cancelled != 0 { throw EngineError(message: "Transcription annulée.") } }
func emit(_ progress: Double, _ stage: String, _ message: String) {
    let obj: [String: Any] = ["progress": min(1, max(0, progress)), "stage": stage, "message": message]
    if let data = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: data, encoding: .utf8) {
        print(str); fflush(stdout)
    }
}
func appendLE<T: FixedWidthInteger>(_ val: T, _ data: inout Data) { var v = val.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
func wavHeader(_ bytes: UInt32) -> Data {
    var data = Data("RIFF".utf8); appendLE(bytes + 36, &data); data.append(Data("WAVEfmt ".utf8)); appendLE(UInt32(16), &data)
    appendLE(UInt16(1), &data); appendLE(UInt16(1), &data); appendLE(UInt32(16000), &data); appendLE(UInt32(32000), &data)
    appendLE(UInt16(2), &data); appendLE(UInt16(16), &data); data.append(Data("data".utf8)); appendLE(bytes, &data); return data
}
func extractAudio(_ source: URL, _ dest: URL) async throws -> Double {
    let asset = AVURLAsset(url: source)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0, duration < 18 * 3600 else { throw EngineError(message: "Durée du média invalide (maximum : 18 heures).") }
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard !tracks.isEmpty else { throw EngineError(message: "Ce média ne contient aucune piste audio.") }
    let reader = try AVAssetReader(asset: asset)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw EngineError(message: "Le format audio ne peut pas être décodé par macOS.") }
    reader.add(output)
    FileManager.default.createFile(atPath: dest.path, contents: wavHeader(0))
    let file = try FileHandle(forWritingTo: dest); defer { try? file.close() }
    try file.seekToEnd()
    guard reader.startReading() else { throw reader.error ?? EngineError(message: "Impossible de lire la piste audio.") }
    var count: Int64 = 0; var peak: Int = 0; var lastProgress = -1
    let zeros = Data(repeating: 0, count: 32000)
    while let sample = output.copyNextSampleBuffer() {
        do { try checkCancelled() } catch { reader.cancelReading(); throw error }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        // Preserve the source timeline, including delayed audio tracks and gaps.
        let target = pts.isFinite ? max(0, Int64((pts * 16000).rounded()) * 2) : count
        var gap = target - count
        while gap > 2 {
            let n = min(Int64(zeros.count), gap); try file.write(contentsOf: zeros.prefix(Int(n))); count += n; gap -= n
        }
        let size = CMBlockBufferGetDataLength(block)
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
        guard status == kCMBlockBufferNoErr else { throw EngineError(message: "Erreur de décodage audio.") }
        data.withUnsafeBytes { bytes in
            for v in bytes.bindMemory(to: Int16.self) { peak = max(peak, abs(Int(Int16(littleEndian: v)))) }
        }
        // Overlapping sample timestamps can occur for compressed audio priming.
        let overlap = max(0, Int(count - target)); if overlap < data.count { let tail = data.dropFirst(overlap); try file.write(contentsOf: tail); count += Int64(tail.count) }
        let percent = Int(min(1, Double(count) / 32000 / duration) * 100)
        if percent != lastProgress { emit(Double(percent) / 100 * 0.08, "audio", "Préparation de la piste audio…"); lastProgress = percent }
    }
    guard reader.status == .completed else { throw reader.error ?? EngineError(message: "Lecture audio interrompue.") }
    guard count > 0, peak > 8 else { throw EngineError(message: "La piste audio est silencieuse : aucune parole à transcrire.") }
    guard count < Int64(UInt32.max) - 36 else { throw EngineError(message: "Piste audio trop longue.") }
    try file.seek(toOffset: 0); try file.write(contentsOf: wavHeader(UInt32(count)))
    return duration
}
func balancedLines(_ text: String, lines: Int, limit: Int) -> String {
    guard lines > 1, text.count > limit else { return text }
    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard words.count > 1 else { return text }
    var best = 1, score = Int.max
    for n in 1..<words.count {
        let a = words[..<n].joined(separator: " ").count, b = words[n...].joined(separator: " ").count
        let s = abs(a-b) + max(0,a-limit)*10 + max(0,b-limit)*10
        if s < score { score = s; best = n }
    }
    return words[..<best].joined(separator: " ") + "\n" + words[best...].joined(separator: " ")
}
func makeCues(_ raw: [String: Any], duration: Double, lines: Int, limit: Int, maxDuration: Double) -> [Cue] {
    let segments = raw["transcription"] as? [[String: Any]] ?? []
    var words = [Word]()
    var lastEnd = 0.0
    for seg in segments {
        let off = seg["offsets"] as? [String: Double] ?? [:]
        let segStart = max(lastEnd, (off["from"] ?? 0)/1000), segEnd = min(duration, (off["to"] ?? 0)/1000)
        guard segEnd > segStart else { continue }
        let text = (seg["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        var local = [Word]()
        for token in seg["tokens"] as? [[String: Any]] ?? [] {
            let t = token["text"] as? String ?? ""
            guard !t.isEmpty, !t.hasPrefix("[_"), !t.hasPrefix("<|") else { continue }
            let o = token["offsets"] as? [String: Double] ?? [:]
            let s = max(segStart, min(segEnd, (o["from"] ?? (segStart*1000))/1000))
            let e = max(s, min(segEnd, (o["to"] ?? (s*1000))/1000))
            if t.first?.isWhitespace == true || local.isEmpty {
                local.append(Word(text: t.trimmingCharacters(in: .whitespacesAndNewlines), start: s, end: e))
            } else { local[local.count-1].text += t; local[local.count-1].end = max(local[local.count-1].end, e) }
        }
        local.removeAll { $0.text.isEmpty }
        if local.isEmpty {
            let split = text.split(whereSeparator: { $0.isWhitespace }); let delta = (segEnd-segStart)/Double(max(1,split.count))
            local = split.enumerated().map { Word(text:String($0.element),start:segStart+Double($0.offset)*delta,end:segStart+Double($0.offset+1)*delta) }
        }
        // Invalid or absent token times receive an even allocation within their original segment.
        if local.last!.end <= local.first!.start || local.contains(where: { $0.end <= $0.start }) {
            let delta = (segEnd-segStart)/Double(local.count)
            for n in local.indices { local[n].start = segStart+Double(n)*delta; local[n].end = segStart+Double(n+1)*delta }
        }
        for n in local.indices { local[n].start = max(lastEnd, local[n].start); local[n].end = max(local[n].start+0.001, local[n].end); lastEnd = local[n].end }
        words += local
    }
    var cues = [Cue](), group = [Word]()
    func flush() {
        guard let first = group.first, let last = group.last else { return }
        let text = balancedLines(group.map(\.text).joined(separator: " "), lines: lines, limit: limit)
        cues.append(Cue(start:first.start,end:min(duration,max(first.start+0.1,last.end)),text:text,words:group)); group.removeAll()
    }
    for word in words {
        if let first = group.first, let last = group.last {
            let candidate = (group + [word]).map(\.text)
            var requiredLines = 1, width = 0
            for part in candidate { if width > 0 && width+1+part.count > limit { requiredLines += 1; width = part.count } else { width += (width > 0 ? 1 : 0)+part.count } }
            if requiredLines > lines || word.end-first.start > maxDuration || word.start-last.end > 0.65 { flush() }
        }
        group.append(word)
        if ".!?…".contains(word.text.last ?? " "), let first = group.first, word.end-first.start >= 1 { flush() }
    }
    flush()
    for n in cues.indices { let next = n+1 < cues.count ? cues[n+1].start : duration; cues[n].end = min(next,max(cues[n].end,min(cues[n].start+0.8,duration))) }
    return cues.filter { $0.end > $0.start }
}
@main struct Main {
    static func main() async {
        signal(SIGTERM, cancelHandler); signal(SIGINT, cancelHandler)
        do { try await run() } catch {
            let data = try? JSONSerialization.data(withJSONObject:["event":"error", "message":error.localizedDescription])
            if let data { FileHandle.standardError.write(data); FileHandle.standardError.write(Data([10])) }
            exit(cancelled != 0 ? 130 : 1)
        }
    }
    static func run() async throws {
        var args = [String:String](); let list = Array(CommandLine.arguments.dropFirst()); var i=0
        while i<list.count { guard list[i].hasPrefix("--"), i+1<list.count else { throw EngineError(message:"Arguments invalides.") }; args[list[i]]=list[i+1]; i+=2 }
        guard let input=args["--input"], let output=args["--output"] else { throw EngineError(message:"Usage : transcribe --input MEDIA --output TRANSCRIPTION.json [--context TEXTE]") }
        let lines = Int(args["--lines"] ?? "2") ?? 2, limit = Int(args["--max-chars"] ?? "42") ?? 42
        let maxDuration = Double(args["--max-duration"] ?? "6") ?? 6
        guard (1...2).contains(lines), (12...100).contains(limit), maxDuration.isFinite, (1...20).contains(maxDuration) else { throw EngineError(message:"Paramètres de sous-titres invalides.") }
        let bin = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let resources = bin.deletingLastPathComponent()
        let model = URL(fileURLWithPath:args["--model"] ?? resources.appendingPathComponent("models/ggml-large-v3-q5_0.bin").path)
        let vad = resources.appendingPathComponent("models/ggml-silero-v6.2.0.bin")
        let cli = bin.appendingPathComponent("whisper-cli")
        guard FileManager.default.isExecutableFile(atPath:cli.path), FileManager.default.fileExists(atPath:model.path), FileManager.default.fileExists(atPath:vad.path) else { throw EngineError(message:"Le moteur ou les modèles Whisper sont absents. Réinstallez l’application.") }
        let source=URL(fileURLWithPath:input).standardizedFileURL
        guard source.path != URL(fileURLWithPath:output).standardizedFileURL.path else { throw EngineError(message:"Le fichier de sortie doit être différent du média source.") }
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("artcraft-whisper-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); defer { try? FileManager.default.removeItem(at:temp) }
        let audio=temp.appendingPathComponent("audio.wav"), result=temp.appendingPathComponent("whisper")
        let duration=try await extractAudio(source,audio)
        try checkCancelled(); emit(0.08,"model","Chargement de Whisper large-v3…")
        let process=Process(); process.executableURL=cli
        var flags=["-m",model.path,"-f",audio.path,"-l","fr","-ojf","-of",result.path,"-pp","-bs","5","-bo","5","-t","6","--vad","-vm",vad.path,"-vt","0.45","-vp","250","-vsd","300"]
        if let context=args["--context"], !context.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { flags += ["--prompt",String(context.prefix(1200)),"--carry-initial-prompt"] }
        process.arguments=flags
        let pipe=Pipe(); process.standardOutput=pipe; process.standardError=pipe
        try process.run(); childPID=process.processIdentifier
        if cancelled != 0 { process.terminate() }
        var tail="", log=""
        let regex=try NSRegularExpression(pattern:"progress = +([0-9]+)%")
        while true {
            let chunk=pipe.fileHandleForReading.availableData; if chunk.isEmpty { break }
            let s=String(decoding:chunk,as:UTF8.self); tail+=s; log+=s; if log.count>16000 { log=String(log.suffix(16000)) }
            if let match=regex.matches(in:tail,range:NSRange(tail.startIndex...,in:tail)).last, let range=Range(match.range(at:1),in:tail), let pct=Double(tail[range]) { emit(0.1+min(pct,100)/100*0.87,"transcription","Transcription française : \(Int(pct)) %") }
            if tail.count>1000 { tail=String(tail.suffix(1000)) }
        }
        process.waitUntilExit(); childPID=0; try checkCancelled()
        guard process.terminationStatus == 0 else {
            try? log.write(to:temp.appendingPathComponent("engine.log"),atomically:true,encoding:.utf8)
            throw EngineError(message:"Whisper n’a pas pu terminer la transcription. \(log.suffix(1000))")
        }
        emit(0.98,"layout","Mise en forme des sous-titres…")
        let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:result.appendingPathExtension("json"))) as? [String:Any] ?? [:]
        let cues=makeCues(raw,duration:duration,lines:lines,limit:limit,maxDuration:maxDuration)
        guard !cues.isEmpty else { throw EngineError(message:"Aucune parole détectée. Vérifiez la piste audio du média.") }
        let transcript=Transcript(source:source.path,duration:duration,segments:cues)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(transcript).write(to:URL(fileURLWithPath:output),options:.atomic)
        emit(1,"complete","Transcription terminée : \(cues.count) sous-titres.")
    }
}
