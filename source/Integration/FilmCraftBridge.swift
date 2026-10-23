import AppKit
import Foundation
import Darwin

// Optional integration with FilmCraft's documented JSON-lines channel. No host files or
// preferences are patched, and a running editor is never restarted. Call blocking methods
// on a worker queue. SRT export remains available when the host has no control connection.
struct FilmCraftContext: Equatable, Codable {
    var trackKey: String { "\(processID)|\(projectPath ?? projectName)|\(sequenceID)" }
    let processID: Int32
    let projectName: String
    let projectPath: String?
    let sequenceID: Int64
    let sequenceName: String
    let revision: Int64
    func sameTarget(as other: Self) -> Bool {
        processID == other.processID && projectName == other.projectName &&
        projectPath == other.projectPath && sequenceID == other.sequenceID
    }
}

struct FilmCraftCaptionStyle {
    var font = "Helvetica Neue"
    var size = 54.0
    var color = "#ffffffff"
    var background = false
    var backgroundColor = "#000000bf"
    var outline = 2.0
    var outlineColor = "#000000ff"
    var align = "center"
    var anchor = "bottom"
    var margin = 0.08
    var lineSpacing = 1.25
    fileprivate func parameters(track: Int64) throws -> [String: Any] {
        guard !font.isEmpty, (4...400).contains(size), (0...40).contains(outline),
              (0...0.45).contains(margin), (0.8...4).contains(lineSpacing),
              ["left", "center", "right"].contains(align), ["top", "middle", "bottom"].contains(anchor),
              [color, backgroundColor, outlineColor].allSatisfy({ $0.range(of: "^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$", options: .regularExpression) != nil }) else {
            throw FilmCraftBridgeError.message("Le style des sous-titres contient une valeur invalide.")
        }
        return ["track": track, "font": font, "size": size, "color": color, "background": background,
                "backgroundColor": backgroundColor, "outline": outline, "outlineColor": outlineColor,
                "align": align, "anchor": anchor, "margin": margin, "lineSpacing": lineSpacing]
    }
}
struct FilmCraftTitleBinding {let trackID:Int64;var clips:[Int64]}
struct FilmCraftTitleResult {let context:FilmCraftContext;let binding:FilmCraftTitleBinding;let message:String}
struct FilmCraftCue { let start: Double; let end: Double; let text: String }
struct FilmCraftImportResult {
    let context: FilmCraftContext
    let trackID: Int64
    let captions: Int
    let message: String
}
enum FilmCraftBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class FilmCraftBridge {
    static let shared: FilmCraftBridge = {
        func arg(_ name:String)->String? {guard let i=CommandLine.arguments.firstIndex(of:name),i+1<CommandLine.arguments.count else{return nil};return CommandLine.arguments[i+1]}
        if CommandLine.arguments.contains("--qa-timeline"),let pid=arg("--qa-host-pid").flatMap(Int32.init),let port=arg("--qa-host-port").flatMap(UInt16.init),port != FilmCraftBridge.port {return FilmCraftBridge(connectionPort:port,hostPID:pid)}
        return FilmCraftBridge()
    }()
    private var titleBindings:[String:FilmCraftTitleBinding]=[:]
    private let connectionPort: UInt16
    private let hostPID: Int32?
    init(connectionPort:UInt16 = FilmCraftBridge.port,hostPID:Int32?=nil){self.connectionPort=connectionPort;self.hostPID=hostPID}
    static let bundleID = "ai.storyteller.filmcraft"
    static let port: UInt16 = 47873
    static let manualImportMessage = "La session FilmCraft actuelle n’a pas de connexion compagnon. Exportez le fichier SRT, puis importez-le dans FilmCraft avec Fichier > Importer. Pour activer l’envoi direct, enregistrez votre projet, quittez FilmCraft vous-même, puis ouvrez-le depuis ce compagnon."

    func openFilmCraft(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
                running.activate(options: [])
                completion(.success(()))
                return
            }
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
                completion(.failure(FilmCraftBridgeError.message("FilmCraft n’est pas installé dans Applications.")))
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = ["--control", String(Self.port)]
            config.activates = true
            NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
                if let error { completion(.failure(error)) } else { completion(.success(())) }
            }
        }
    }

    func snapshot() throws -> FilmCraftContext {
        let connection = try FilmCraftConnection(port: connectionPort)
        return try context(connection)
    }

    func importCaptions(srtURL: URL, style: FilmCraftCaptionStyle, expected: FilmCraftContext? = nil) throws -> FilmCraftImportResult {
        _ = try style.parameters(track: 0) // validate before any host mutation
        guard srtURL.isFileURL, srtURL.pathExtension.lowercased() == "srt",
              FileManager.default.isReadableFile(atPath: srtURL.path) else {
            throw FilmCraftBridgeError.message("Exportez d’abord un fichier SRT lisible pour l’envoyer à FilmCraft.")
        }
        let connection = try FilmCraftConnection(port: connectionPort)
        guard let commands = try connection.call("engine.commands") as? [[String: Any]] else {
            throw FilmCraftBridgeError.message("FilmCraft renvoie un protocole incompatible. Utilisez l’import SRT.")
        }
        let available = Set(commands.compactMap { $0["id"] as? String })
        guard ["captions.import", "captions.setStyle", "captions.setTrack", "captions.list", "project.inspect", "sequence.inspect"].allSatisfy(available.contains) else {
            throw FilmCraftBridgeError.message("Cette version de FilmCraft ne propose pas toutes les commandes nécessaires. Utilisez Fichier > Importer pour le SRT.")
        }
        let before = try context(connection)
        if let expected, expected != before {
            throw FilmCraftBridgeError.message("Le projet ou la séquence FilmCraft a changé. Aucun sous-titre n’a été ajouté. Vérifiez la séquence cible, puis réessayez.")
        }
        // Do not silently choose/create a new sequence or overwrite an existing caption track.
        let checked = try context(connection)
        guard checked == before else { throw FilmCraftBridgeError.message("Le projet FilmCraft a changé pendant la préparation. Aucun sous-titre n’a été ajouté.") }
        var inserted = false
        do {
            guard let imported = try connection.execute("captions.import", ["path": srtURL.path, "name": "Sous-titres français"]) as? [String: Any],
                  let track = (imported["track"] as? NSNumber)?.int64Value,
                  let seq = (imported["sequence"] as? NSNumber)?.int64Value,
                  let count = (imported["captions"] as? NSNumber)?.intValue, count > 0 else {
                throw FilmCraftBridgeError.message("FilmCraft n’a pas confirmé l’import. Vérifiez ses pistes avant de réessayer pour éviter un doublon.")
            }
            inserted = true
            let after = try context(connection)
            guard seq == before.sequenceID, after.sameTarget(as: before), after.revision == before.revision + 1 else {
                throw FilmCraftBridgeError.message("Les sous-titres ont été importés, mais le contexte FilmCraft a changé. Leur style n’a pas été appliqué ; vérifiez la nouvelle piste dans FilmCraft.")
            }
            _ = try connection.execute("captions.setStyle", style.parameters(track: track))
            let styled = try context(connection)
            guard styled.sameTarget(as: before), styled.revision == after.revision + 1 else {
                throw FilmCraftBridgeError.message("Les sous-titres sont importés ; le projet a changé pendant l’application du style. Vérifiez la piste dans FilmCraft.")
            }
            _ = try connection.execute("captions.setTrack", ["track": track, "language": "fr"])
            guard let list = try connection.execute("captions.list", ["track": track]) as? [String: Any],
                  let tracks = list["tracks"] as? [[String: Any]],
                  tracks.contains(where: { ($0["id"] as? NSNumber)?.int64Value == track }) else {
                throw FilmCraftBridgeError.message("Les sous-titres ont été envoyés, mais leur vérification a échoué. Vérifiez la piste dans FilmCraft.")
            }
            let warnings = (imported["warnings"] as? [String] ?? []).joined(separator: " ")
            let final = try context(connection)
            guard final.sameTarget(as:before),final.revision == styled.revision + 1 else {throw FilmCraftBridgeError.message("Le montage a changé pendant l’envoi. Vérifiez la piste dans FilmCraft.")}
            return FilmCraftImportResult(context:final,trackID: track, captions: count, message: "\(count) sous-titres ajoutés avec leur style dans « \(before.sequenceName) »." + (warnings.isEmpty ? "" : " " + warnings))
        } catch {
            // Never retry a write: an interrupted reply does not mean the host rejected it.
            if inserted { throw FilmCraftBridgeError.message("Les sous-titres ont été importés. Vérifiez leur piste et leur style dans FilmCraft avant tout nouvel envoi. \(error.localizedDescription)") }
            throw error
        }
    }

    // Update only the numeric track created in this companion session. Other tracks
    // are never inferred from their labels, selected or deleted.
    func updateCaptions(cues:[FilmCraftCue],track:Int64,style:FilmCraftCaptionStyle,expected:FilmCraftContext) throws -> FilmCraftImportResult {
        _ = try style.parameters(track:track)
        var end=0.0
        for cue in cues {
            guard cue.start.isFinite,cue.end.isFinite,cue.start >= end,cue.end > cue.start,
                  cue.end < 864000,!cue.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                throw FilmCraftBridgeError.message("Les sous-titres contiennent un texte ou un minutage invalide.")
            }
            end=cue.end
        }
        let c=try FilmCraftConnection(port:connectionPort)
        guard try context(c) == expected else {throw FilmCraftBridgeError.message("Le montage a changé. Aucun sous-titre n’a été modifié. Relancez la transcription de la timeline.")}
        guard let listing=try c.execute("captions.list",["track":track]) as? [String:Any],
              let tracks=listing["tracks"] as? [[String:Any]],
              let existing=tracks.first(where:{($0["id"] as? NSNumber)?.int64Value == track}),
              existing["locked"] as? Bool != true,
              let captions=existing["captions"] as? [[String:Any]] else {
            throw FilmCraftBridgeError.message("La piste du compagnon est absente ou verrouillée. Aucune nouvelle piste n’a été créée.")
        }
        let ids=captions.compactMap{($0["id"] as? NSNumber)?.int64Value}
        guard ids.count == captions.count else {throw FilmCraftBridgeError.message("Piste de sous-titres incompatible.")}
        guard let sequence=try c.execute("sequence.inspect",["item":expected.sequenceID]) as? [String:Any],
              let settings=sequence["settings"] as? [String:Any],
              let rate=settings["frame_rate"] as? [String:Any],
              let num=(rate["num"] as? NSNumber)?.doubleValue,
              let den=(rate["den"] as? NSNumber)?.doubleValue,num > 0,den > 0 else {
            throw FilmCraftBridgeError.message("Cadence de la séquence indisponible.")
        }
        let frameTicks=(254016000000.0 * den / num).rounded()
        var previousEnd:Int64=0
        let timed=try cues.map {cue -> (FilmCraftCue,Int64,Int64) in
            let a=Int64((cue.start * 254016000000.0 / frameTicks).rounded()) * Int64(frameTicks)
            let b=Int64((cue.end * 254016000000.0 / frameTicks).rounded()) * Int64(frameTicks)
            guard a >= previousEnd,b > a else {throw FilmCraftBridgeError.message("Un sous-titre est trop court ou chevauche son voisin à la cadence du montage. Ajustez ses temps.")}
            previousEnd=b
            return (cue,a,b)
        }
        var current=expected
        func write(_ command:String,_ params:[String:Any]) throws {
            guard try context(c) == current else {throw FilmCraftBridgeError.message("Le montage a changé pendant la mise à jour. L’envoi est interrompu.")}
            _ = try c.execute(command,params)
            let next=try context(c)
            guard next.sameTarget(as:current),next.revision == current.revision + 1 else {throw FilmCraftBridgeError.message("Le montage a changé pendant la mise à jour. Vérifiez la piste du compagnon.")}
            current=next
        }
        do {
            if !ids.isEmpty {try write("captions.delete",["captions":ids,"ripple":false])}
            for (cue,a,b) in timed {
                try write("captions.add",["track":track,"text":cue.text,"time":a,"durationSeconds":Double(b-a)/254016000000.0])
            }
            try write("captions.setStyle",style.parameters(track:track))
            guard let result=try c.execute("captions.list",["track":track]) as? [String:Any],
                  let tracks=result["tracks"] as? [[String:Any]],
                  let updated=tracks.first,
                  (updated["captions"] as? [Any])?.count == cues.count else {throw FilmCraftBridgeError.message("La vérification de la piste mise à jour a échoué.")}
            return FilmCraftImportResult(context:current,trackID:track,captions:cues.count,message:"\(cues.count) sous-titres mis à jour dans « \(expected.sequenceName) » · une seule piste.")
        }catch {throw FilmCraftBridgeError.message("Mise à jour interrompue. Aucune piste supplémentaire n’a été créée. Vérifiez la piste dans FilmCraft ; ses modifications restent annulables dans le logiciel. \(error.localizedDescription)")}
    }

    func sendTitles(cues:[FilmCraftCue],style:SubtitleStyle,expected:FilmCraftContext,binding:FilmCraftTitleBinding?) throws -> FilmCraftTitleResult {
        guard !cues.isEmpty,style.fontSize.isFinite,(12...160).contains(style.fontSize),
              (0...1).contains(style.positionX),(0...1).contains(style.positionY) else {throw FilmCraftBridgeError.message("Paramètres des titres invalides.")}
        let c=try FilmCraftConnection(port:connectionPort)
        guard try context(c) == expected else {throw FilmCraftBridgeError.message("Le montage a changé depuis la transcription. Transcrivez à nouveau la séquence avant l’envoi.")}
        guard let sequence=try c.execute("sequence.inspect",["item":expected.sequenceID]) as? [String:Any],
              let settings=sequence["settings"] as? [String:Any],let w=(settings["width"] as? NSNumber)?.doubleValue,
              let h=(settings["height"] as? NSNumber)?.doubleValue,
              let rate=settings["frame_rate"] as? [String:Any],let num=(rate["num"] as? NSNumber)?.doubleValue,
              let den=(rate["den"] as? NSNumber)?.doubleValue,num>0,den>0,w>0,h>0,
              let video=sequence["video"] as? [[String:Any]] else {throw FilmCraftBridgeError.message("Format de la séquence indisponible.")}
        let frameTicks=(254016000000.0*den/num).rounded()
        var previous:Int64=0
        let timed=try cues.map {cue -> (FilmCraftCue,Int64,Int64) in
            guard cue.start.isFinite,cue.end.isFinite,cue.start>=0,cue.end<864000 else {throw FilmCraftBridgeError.message("Minutage invalide.")}
            let a=Int64((cue.start*254016000000.0/frameTicks).rounded())*Int64(frameTicks)
            let b=Int64((cue.end*254016000000.0/frameTicks).rounded())*Int64(frameTicks)
            guard a>=previous,b>a,!cue.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw FilmCraftBridgeError.message("Un sous-titre est trop court ou chevauche le suivant à la cadence du montage.")}
            previous=b;return (cue,a,b)
        }
        _ = try c.execute("fonts.list",["system":true])
        var current=expected
        @discardableResult func write(_ command:String,_ params:[String:Any]) throws -> Any {
            guard try context(c)==current else {throw FilmCraftBridgeError.message("Le montage a changé pendant l’envoi. Transfert interrompu.")}
            let result=try c.execute(command,params);let next=try context(c)
            guard next.sameTarget(as:current),next.revision==current.revision+1 else {throw FilmCraftBridgeError.message("Le montage a changé pendant l’envoi. Vérifiez la piste ArtCraft.")}
            current=next;return result
        }
        var owned=titleBindings[expected.trackKey] ?? binding
        let trackIndex:Int
        if let old=owned {
            guard let index=video.firstIndex(where:{($0["id"] as? NSNumber)?.int64Value==old.trackID}),
                  video[index]["locked"] as? Bool != true,
                  let items=video[index]["items"] as? [[String:Any]],
                  Set(items.compactMap{($0["clip"] as? NSNumber)?.int64Value})==Set(old.clips) else {
                throw FilmCraftBridgeError.message("La piste ArtCraft est verrouillée ou son contenu a été modifié dans FilmCraft. Aucun titre existant n’a été effacé.")
            }
            trackIndex=index
            if !old.clips.isEmpty {_ = try write("edit.clear",["clips":old.clips])}
            owned=FilmCraftTitleBinding(trackID:old.trackID,clips:[])
        }else {
            guard let result=try write("sequence.addTracks",["video":1,"audio":0]) as? [String:Any],
                  let ids=result["video"] as? [NSNumber],let id=ids.first?.int64Value else {throw FilmCraftBridgeError.message("La piste de titres n’a pas été confirmée.")}
            trackIndex=video.count;owned=FilmCraftTitleBinding(trackID:id,clips:[])
            _ = try write("timeline.setTrack",["track":id,"name":"Sous-titres · ArtCraft"])
        }
        guard var track=owned else {throw FilmCraftBridgeError.message("Piste indisponible.")}
        titleBindings[expected.trackKey]=track
        let size=style.fontSize*h/1080
        let font=NSFont(name:style.fontName,size:size) ?? NSFont.systemFont(ofSize:size)
        for (cue,a,b) in timed {
            let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
            let bounds=(cue.text as NSString).boundingRect(with:NSSize(width:w*0.9,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font,.paragraphStyle:paragraph])
            let width=min(w*0.9,ceil(bounds.width)+4),height=ceil(bounds.height)+4
            let x=(w-width)*style.positionX+width/2
            let y=(h-height)*style.positionY+font.ascender
            guard let result=try write("graphics.newText",["text":cue.text,"newClip":true,"track":trackIndex,"time":a,"seconds":Double(b-a)/254016000000.0,"font":style.fontFamily,"fontStyle":style.fontFace,"size":size,"position":[x,y]]) as? [String:Any],
                  let clip=(result["clip"] as? NSNumber)?.int64Value else {throw FilmCraftBridgeError.message("Le titre n’a pas été confirmé.")}
            track.clips.append(clip);titleBindings[expected.trackKey]=track
            _ = try write("graphics.set",["clip":clip,"layer":0,"props":["align":"center","fill_color":style.color,"stroke":style.outline>0,"stroke_width":style.outline*h/1080,"stroke_color":style.outlineColor,"faux_bold":false]])
        }
        return FilmCraftTitleResult(context:current,binding:track,message:"\(cues.count) sous-titres dans « \(expected.sequenceName) » · piste ArtCraft mise à jour.")
    }

    // Render the active sequence mix, including cuts, gaps, muted tracks and effects.
    func exportTimeline(to url: URL, expected: FilmCraftContext, cancelled: () -> Bool,
                        progress: (Double) -> Void) throws -> FilmCraftContext {
        let c = try FilmCraftConnection(port: connectionPort)
        guard try context(c) == expected else { throw FilmCraftBridgeError.message("La timeline a changé. Relancez la transcription.") }
        guard let reply = try c.execute("file.exportMedia", ["path":url.path, "sequence":expected.sequenceID,
            "format":"wav", "range":"entire", "wait":false]) as? [String:Any],
            let job = reply["job"] as? NSNumber else { throw FilmCraftBridgeError.message("FilmCraft n’a pas démarré le mixage audio.") }
        let deadline = Date().addingTimeInterval(18 * 3600)
        while Date() < deadline {
            if cancelled() {
                _ = try? c.execute("jobs.cancel", ["id":job])
                throw FilmCraftBridgeError.message("Préparation de la timeline annulée.")
            }
            guard let jobs = try c.execute("jobs.list", [:]) as? [[String:Any]],
                  let state = jobs.first(where: { ($0["id"] as? NSNumber) == job }) else {
                throw FilmCraftBridgeError.message("Le mixage audio n’est plus disponible dans FilmCraft.")
            }
            progress((state["progress"] as? NSNumber)?.doubleValue ?? 0)
            if state["finished"] as? Bool == true {
                if let error = (state["result"] as? [String:Any])?["error"] as? String { throw FilmCraftBridgeError.message(error) }
                if let offline = state["offlineMedia"] as? [Any], !offline.isEmpty {
                    throw FilmCraftBridgeError.message("Des médias de la timeline sont hors ligne. Reliez-les dans FilmCraft avant de transcrire.")
                }
                guard FileManager.default.isReadableFile(atPath:url.path),
                      (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) > 44 else {
                    throw FilmCraftBridgeError.message("Le mixage audio FilmCraft est vide.")
                }
                let after = try context(c)
                guard after.sameTarget(as:expected), after.revision == expected.revision else {
                    throw FilmCraftBridgeError.message("Le montage a changé pendant le mixage. Relancez la transcription pour analyser la bonne version.")
                }
                return after
            }
            Thread.sleep(forTimeInterval:0.25)
        }
        _ = try? c.execute("jobs.cancel", ["id":job])
        throw FilmCraftBridgeError.message("Le mixage de la timeline a dépassé le délai autorisé.")
    }

    private func context(_ connection: FilmCraftConnection) throws -> FilmCraftContext {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).filter { hostPID == nil || $0.processIdentifier == hostPID }
        guard instances.count == 1, let running = instances.first else {
            throw FilmCraftBridgeError.message(instances.isEmpty ? "Ouvrez FilmCraft et la séquence à sous-titrer." : "Plusieurs sessions FilmCraft sont ouvertes. Utilisez l’import SRT dans la fenêtre de votre choix.")
        }
        guard let project = try connection.execute("project.inspect", [:]) as? [String: Any],
              let name = project["name"] as? String,
              let revision = (project["revision"] as? NSNumber)?.int64Value,
              let sequence = (project["activeSequence"] as? NSNumber)?.int64Value,
              let details = try connection.execute("sequence.inspect", ["item": sequence]) as? [String: Any],
              (details["id"] as? NSNumber)?.int64Value == sequence else {
            throw FilmCraftBridgeError.message("Ouvrez une séquence dans FilmCraft avant d’envoyer les sous-titres.")
        }
        return FilmCraftContext(processID: running.processIdentifier, projectName: name,
            projectPath: project["path"] as? String, sequenceID: sequence,
            sequenceName: details["name"] as? String ?? "Séquence", revision: revision)
    }
}

// Blocking loopback transport with bounded replies/timeouts and SIGPIPE suppressed.
// Protocol is unauthenticated in FilmCraft 0.12.0; do not expose a remote endpoint.
private final class FilmCraftConnection {
    private let fd: Int32
    private var buffer = Data()
    private var nextID = 0
    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FilmCraftBridgeError.message(FilmCraftBridge.manualImportMessage) }
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if result != 0 { close(fd); throw FilmCraftBridgeError.message(FilmCraftBridge.manualImportMessage) }
    }
    deinit { close(fd) }
    func execute(_ command: String, _ params: [String: Any]) throws -> Any {
        try call("engine.execute", ["command": command, "params": params])
    }
    func call(_ method: String, _ params: [String: Any] = [:]) throws -> Any {
        nextID += 1
        var data = try JSONSerialization.data(withJSONObject: ["id": nextID, "method": method, "params": params])
        data.append(10)
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.send(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
                guard count > 0 else { throw FilmCraftBridgeError.message("Connexion interrompue. Vérifiez les pistes FilmCraft avant de réessayer : l’action a peut-être été exécutée.") }
                sent += count
            }
        }
        while !buffer.contains(10) {
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = Darwin.recv(fd, &bytes, bytes.count, 0)
            guard count > 0 else { throw FilmCraftBridgeError.message("FilmCraft ne répond plus. Vérifiez ses pistes avant de réessayer : l’action a peut-être été exécutée.") }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 8 * 1024 * 1024 else { throw FilmCraftBridgeError.message("La réponse FilmCraft dépasse la taille autorisée.") }
        }
        let end = buffer.firstIndex(of: 10)!
        let line = buffer.prefix(upTo: end)
        buffer.removeSubrange(...end)
        guard let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              (reply["id"] as? NSNumber)?.intValue == nextID, let success = reply["ok"] as? Bool else {
            throw FilmCraftBridgeError.message("Réponse FilmCraft incompatible. Utilisez l’import SRT.")
        }
        guard success else { throw FilmCraftBridgeError.message(reply["error"] as? String ?? "FilmCraft a refusé l’action.") }
        return reply["result"] ?? NSNull()
    }
}
