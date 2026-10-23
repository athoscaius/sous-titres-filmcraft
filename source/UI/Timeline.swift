import AppKit

final class TimelineCancellation {
    private let lock=NSLock()
    private var value=false
    func cancel(){lock.lock();value=true;lock.unlock()}
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return value}
}

extension SubtitleApp {
    func configureTimelineConnection() {
        // FilmCraft reads this supported variable only at startup. Persist across login
        // without patching the host bundle or replacing its executable.
        do {
            let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents",isDirectory:true)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let agent:[String:Any] = ["Label":"local.artcraft.filmcraft-connection", "ProgramArguments":["/bin/launchctl","setenv","FILMCRAFT_CONTROL_PORT",String(FilmCraftBridge.port)],"RunAtLoad":true]
            let data=try PropertyListSerialization.data(fromPropertyList:agent,format:.xml,options:0)
            try data.write(to:dir.appendingPathComponent("local.artcraft.filmcraft-connection.plist"),options:.atomic)
            let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/launchctl");process.arguments=["setenv","FILMCRAFT_CONTROL_PORT",String(FilmCraftBridge.port)]
            try process.run();process.waitUntilExit()
            if process.terminationStatus != 0 {throw SubtitleError.invalid("Activation de la connexion impossible. Ouvrez FilmCraft depuis le compagnon.")}
        } catch {status.stringValue=error.localizedDescription}
    }
    func refreshTimeline() {
        guard timelineMode,!busy,!connectionPollPending else{return}
        connectionPollPending=true
        DispatchQueue.global(qos:.utility).async {
            let result=Result{try FilmCraftBridge.shared.snapshot()}
            DispatchQueue.main.async {
                self.connectionPollPending=false
                guard self.timelineMode,!self.busy else{return}
                switch result {
                case .success(let target):
                    self.liveTimeline=target
                    let displayed=self.timelineTarget ?? target
                    self.titleLabel.stringValue="\(displayed.projectName) · \(displayed.sequenceName)"
                    if self.project.segments.isEmpty {self.status.stringValue="Timeline active : \(target.sequenceName) · prête à sous-titrer."}
                case .failure:
                    self.liveTimeline=nil
                    if self.timelineTarget == nil {
                        self.titleLabel.stringValue="FilmCraft · connexion en attente"
                        self.status.stringValue="Enregistrez puis quittez FilmCraft une première fois, et cliquez Timeline FilmCraft pour le rouvrir connecté."
                    }
                }
            }
        }
    }
    @objc func useTimeline() {
        guard !busy else{return}
        timelineMode=true;timelineTarget=nil;updateUI()
        FilmCraftBridge.shared.openFilmCraft {result in
            if case .failure(let error)=result {self.show(error)}
            self.refreshTimeline()
        }
    }
    func transcribeTimeline() {
        guard !busy,commitCue() else{return}
        contextChanged();layoutChanged()
        let token=TimelineCancellation();timelineExportCancellation=token;busy=true;updateUI();progress.isHidden=false;progress.isIndeterminate=true;progress.startAnimation(nil);status.stringValue="Identification de la timeline active…"
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("ArtCraft Sous-titres IA/Timeline-\(UUID().uuidString)",isDirectory:true)
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let target=try FilmCraftBridge.shared.snapshot()
                try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let audio=cache.appendingPathComponent("Timeline.wav")
                let checked=try FilmCraftBridge.shared.exportTimeline(to:audio,expected:target,cancelled:{token.isCancelled}){value in
                    DispatchQueue.main.async {self.status.stringValue="Mixage audio · \(target.sequenceName)…";self.progress.isIndeterminate=false;self.progress.doubleValue=value}
                }
                guard !token.isCancelled else {throw SubtitleError.invalid("Préparation annulée.")}
                DispatchQueue.main.async {
                    self.timelineExportCancellation=nil;self.busy=false;self.progress.isHidden=true
                    self.timelinePreviousState=(self.project,self.timelineTarget,self.timelineAudioPath);self.record();self.project.videoPath=audio.path;self.project.segments=[];self.project.timelineOffset=0;self.projectURL=nil
                    self.timelineAudioPath=audio.path;self.timelineTarget=checked;self.automaticTransfer=false;self.loadVideo(audio);self.updateUI();self.transcribeMedia()
                }
            } catch {
                try? FileManager.default.removeItem(at:cache)
                DispatchQueue.main.async {
                    self.timelineExportCancellation=nil;self.busy=false;self.progress.isHidden=true;self.progress.stopAnimation(nil);self.updateUI();self.status.stringValue=error.localizedDescription
                    if !token.isCancelled {self.show(error)}
                }
            }
        }
    }
    func restoreTimelineAfterFailure() {
        automaticTransfer=false
        if let state=timelinePreviousState {project=state.0;timelineTarget=state.1;timelineAudioPath=state.2;timelinePreviousState=nil;if !project.videoPath.isEmpty {loadVideo(URL(fileURLWithPath:project.videoPath))}else{player.replaceCurrentItem(with:nil)}}
    }
    func finishTimelineTranscriptionQA() {
        guard let target=timelineTarget else{show(SubtitleError.invalid("QA : cible absente"));return}
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                guard try FilmCraftBridge.shared.snapshot()==target else {throw SubtitleError.invalid("QA : la transcription a modifié le montage avant l’envoi")}
                DispatchQueue.main.async {
                    do {
                        guard self.subtitleButton.isEnabled else {throw SubtitleError.invalid("QA : bouton de sous-titrage indisponible après transcription")}
                        if CommandLine.arguments.contains("--qa-two-step") {try self.checkStyleControls()}
                        print("Two-step workflow OK: transcription completed with unchanged FilmCraft revision; invoking subtitle button separately.")
                        self.sendFilmCraft()
                    }catch{self.show(error)}
                }
            }catch{DispatchQueue.main.async{self.show(error)}}
        }
    }
    func transferBoundTimeline() {
        guard !busy,let target=timelineTarget,!project.segments.isEmpty,commitCue() else{return}
        guard project.videoPath == timelineAudioPath else {show(SubtitleError.invalid("La source a changé. Relancez la transcription de la timeline avant l’envoi."));return}
        do {
            // Timeline audio begins at sequence zero. No manual offset for this mode.
            let raw=try SubtitleFormat.srt(project.segments)
            let temp=FileManager.default.temporaryDirectory.appendingPathComponent("ArtCraft-Timeline-\(UUID().uuidString).srt")
            try raw.write(to:temp,atomically:true,encoding:.utf8)
            let cues=project.segments.map {FilmCraftCue(start:$0.start,end:$0.end,text:$0.text)}
            busy=true;updateUI();cancelButton.isHidden=true;status.stringValue="Ajout des sous-titres dans « \(target.sequenceName) »…"
            DispatchQueue.global(qos:.userInitiated).async {
                defer {try? FileManager.default.removeItem(at:temp)}
                do {
                    let result=try FilmCraftBridge.shared.sendTitles(cues:cues,style:self.project.style,expected:target,binding:self.graphicBindings[target.trackKey])
                    DispatchQueue.main.async {self.busy=false;self.timelineTarget=result.context;self.graphicBindings[target.trackKey]=result.binding;self.updateUI();self.status.stringValue=result.message;if CommandLine.arguments.contains("--qa-timeline") {
                        if CommandLine.arguments.contains("--qa-update-track"),self.timelineQAUpdates == 0 {
                            self.timelineQAUpdates=1
                            do {try self.runQAEditChecks(outputURL:URL(fileURLWithPath:CommandLine.arguments[CommandLine.arguments.firstIndex(of:"--qa-output")!+1]));self.transferBoundTimeline()}catch{self.show(error)}
                        }else if CommandLine.arguments.contains("--qa-update-track"),self.timelineQAUpdates == 1 {
                            self.timelineQAUpdates=2;self.transcribeTimeline()
                        }else if CommandLine.arguments.contains("--qa-update-track"),self.timelineQAUpdates == 2 {
                            self.timelineQAUpdates=3
                            do {try self.runQAEditChecks(outputURL:URL(fileURLWithPath:CommandLine.arguments[CommandLine.arguments.firstIndex(of:"--qa-output")!+1]));self.transferBoundTimeline()}catch{self.show(error)}
                        }else{self.finishQA()}
                    }}
                } catch {DispatchQueue.main.async {self.busy=false;self.updateUI();self.status.stringValue="Transcription conservée · envoi interrompu.";self.show(error)}}
            }
        }catch{show(error)}
    }
}
