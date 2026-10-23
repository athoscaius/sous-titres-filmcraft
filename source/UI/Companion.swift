import AppKit
import AVKit
import UniformTypeIdentifiers

final class SubtitleApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var project = SubtitleProject()
    var savedProject = SubtitleProject()
    var projectURL: URL?
    var undoStates: [SubtitleProject] = []
    var redoStates: [SubtitleProject] = []
    let player = AVPlayer()
    let playerView = AVPlayerView()
    let overlay = SubtitleOverlay()
    let seekSlider=NSSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    let playbackTime=NSTextField(labelWithString:"00:00 / 00:00")
    let table = NSTableView()
    let titleLabel = NSTextField(labelWithString: "Aucune vidéo")
    let countLabel = NSTextField(labelWithString: "Transcription")
    let status = NSTextField(labelWithString: "Détection de la timeline active de FilmCraft…")
    let elapsed = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    let startField = NSTextField(string:"00:00:00,000")
    let endField = NSTextField(string:"00:00:00,000")
    let textEditor = NSTextView()
    let contextField = NSTextField(string: "")
    let lineChoice = NSPopUpButton()
    let maxCharsField = NSTextField(string:"42")
    let maxDurationField = NSTextField(string:"6")
    let fontChoice = NSPopUpButton()
    let sizeField = NSTextField(string:"52")
    let faceChoice = NSPopUpButton()
    var fontFaces: [(name:String,style:String)] = []
    var faceRow: NSStackView!
    let sizeSlider=NSSlider(value:52,minValue:12,maxValue:160,target:nil,action:nil)
    let xSlider=NSSlider(value:50,minValue:0,maxValue:100,target:nil,action:nil)
    let ySlider=NSSlider(value:88,minValue:0,maxValue:100,target:nil,action:nil)
    let sizeValue=NSTextField(labelWithString:"52 px")
    let xValue=NSTextField(labelWithString:"50 %")
    let yValue=NSTextField(labelWithString:"88 %")
    let outlineColorWell=NSColorWell()
    var subtitleButton:PanelButton!
    var graphicBindings:[String:FilmCraftTitleBinding]=[:]
    let outlineField = NSTextField(string:"2")
    let marginField = NSTextField(string:"70")
    let offsetField = NSTextField(string:"0")
    let positionChoice = NSPopUpButton()
    let colorWell = NSColorWell()
    var transcribeButton: PanelButton!
    var cancelButton: PanelButton!
    var importButton: PanelButton!
    var exportButton: PanelButton!
    var openButton: PanelButton!
    var inspector: NSView!
    var editingControls: [NSControl] = []
    var task: Process?
    var progressPipe: Pipe?
    var stderrPipe: Pipe?
    var processBuffer = Data()
    var errorBuffer = Data()
    let pipeLock = NSLock()
    var busy = false
    var currentTaskID: UUID?
    var cancelled = false
    var timer: Timer?
    var startedAt: Date?
    var timeObserver: Any?
    var selectedID: String?
    var editorOriginal = ""
    var startOriginal = ""
    var endOriginal = ""
    var updating = false
    var timelineTracks: [String:Int64] = [:]
    var timelineQAUpdates = 0
    var timelineMode = true
    var timelinePreviousState: (SubtitleProject, FilmCraftContext?, String?)?
    var timelineAudioPath: String?
    var timelineTarget: FilmCraftContext?
    var liveTimeline: FilmCraftContext?
    var timelineTimer: Timer?
    var connectionPollPending = false
    var automaticTransfer = false
    var timelineExportCancellation: TimelineCancellation?
    var previewMode = false
    var selected: Int? { let row = table.selectedRow; return project.segments.indices.contains(row) ? row : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named:.darkAqua)
        menu(); buildWindow(); updateUI()
        if let icon = Bundle.main.url(forResource:"AppIcon-v2",withExtension:"png").flatMap(NSImage.init(contentsOf:)) { NSApp.applicationIconImage = icon }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        timeObserver = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.08,preferredTimescale:600),queue:.main) { [weak self] _ in self?.updateOverlay() }
        if !CommandLine.arguments.contains("--preview-ui") && !CommandLine.arguments.contains("--qa-video") && !CommandLine.arguments.contains("--qa-timeline") {
            configureTimelineConnection()
            refreshTimeline()
            timelineTimer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in self?.refreshTimeline()}
        }
        if CommandLine.arguments.contains("--qa-timeline") {
            project.context="Grenoble, Élodie, FilmCraft";updateUI()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.transcribeTimeline()}
        }
        if CommandLine.arguments.contains("--preview-ui") { makePreview() }
        if let index=CommandLine.arguments.firstIndex(of:"--qa-video"),index+1<CommandLine.arguments.count {timelineMode=false;project.videoPath=CommandLine.arguments[index+1];if let contextIndex=CommandLine.arguments.firstIndex(of:"--qa-context"),contextIndex+1<CommandLine.arguments.count {project.context=CommandLine.arguments[contextIndex+1]};savedProject=project;loadVideo(URL(fileURLWithPath:project.videoPath));updateUI();DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.transcribe()}}
    }
    func applicationDidBecomeActive(_ notification:Notification) {if window != nil {refreshFonts();refreshFaces(preserve:project.style.fontName)}}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if busy {alert("Traitement en cours", "Attendez la fin de l’envoi, ou annulez la transcription avant de quitter.");return .terminateCancel}
        return .terminateNow
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        if busy {alert("Traitement en cours", "Attendez la fin de l’envoi, ou annulez la transcription avant de fermer.");return false}
        return true
    }
    func menu() {
        let main = NSMenu(); NSApp.mainMenu = main
        func submenu(_ title:String)->NSMenu { let item=NSMenuItem(); item.title=title; main.addItem(item); let m=NSMenu(title:title); item.submenu=m; return m }
        func item(_ m:NSMenu,_ title:String,_ action:Selector,_ key:String="") { let i=NSMenuItem(title:title,action:action,keyEquivalent:key); i.target=self; m.addItem(i) }
        let app=submenu("Sous-titres FilmCraft"); item(app,"À propos…",#selector(about)); app.addItem(.separator()); item(app,"Quitter",#selector(quit),"q")
        let file=submenu("Fichier"); item(file,"Ouvrir une vidéo…",#selector(openVideo),"o"); file.addItem(.separator()); item(file,"Importer un SRT…",#selector(importSRT)); item(file,"Exporter les sous-titres…",#selector(exportSubtitles),"e")
        let edit=submenu("Édition"); item(edit,"Annuler",#selector(undoEdit),"z"); let redo=NSMenuItem(title:"Rétablir",action:#selector(redoEdit),keyEquivalent:"z"); redo.keyEquivalentModifierMask=[.command,.shift];redo.target=self;edit.addItem(redo); edit.addItem(.separator())
        for (t,a,k) in [("Couper",#selector(NSText.cut(_:)),"x"),("Copier",#selector(NSText.copy(_:)),"c"),("Coller",#selector(NSText.paste(_:)),"v"),("Tout sélectionner",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:t,action:a,keyEquivalent:k) }
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() { alert("Sous-titres FilmCraft", "Transcription française locale avec Whisper.\nCorrection manuelle, minutage et styles de sous-titres.\nLes exports ASS conservent le style ; SRT et VTT conservent texte et minutage.") }
    func label(_ text:String,dim:Bool=false,size:CGFloat=12)->NSTextField { let f=NSTextField(labelWithString:text);f.font = .systemFont(ofSize:size); f.textColor=dim ? Palette.dim : Palette.text; return f }
    func section(_ text:String)->NSTextField { let f=label(text,size:13);f.font = .systemFont(ofSize:13,weight:.semibold);return f }
    func stack(_ views:[NSView],vertical:Bool=true,spacing:CGFloat=10)->NSStackView { let s=NSStackView(views:views);s.orientation=vertical ? .vertical : .horizontal;s.spacing=spacing;s.alignment=vertical ? .leading : .centerY;s.distribution = .fill;return s }
    func button(_ title:String,_ action:Selector,primary:Bool=false)->PanelButton { let b=PanelButton(title:title,target:self,action:action);b.isBordered=false;b.primary=primary;b.font = .systemFont(ofSize:12,weight:.medium); b.translatesAutoresizingMaskIntoConstraints=false;b.heightAnchor.constraint(equalToConstant:32).isActive=true;return b }
    func stretch(_ view:NSView,_ width:CGFloat?=nil) { view.translatesAutoresizingMaskIntoConstraints=false;if let w=width { view.widthAnchor.constraint(equalToConstant:w).isActive=true } }
    func fill(_ view:NSView,in parent:NSView,inset:CGFloat=0) { view.translatesAutoresizingMaskIntoConstraints=false;parent.addSubview(view); NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),view.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),view.topAnchor.constraint(equalTo:parent.topAnchor,constant:inset),view.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-inset)]) }
    func field(_ f:NSTextField,width:CGFloat?=nil) { f.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular);f.backgroundColor=Palette.field;f.textColor=Palette.text;f.isBordered=true;f.bezelStyle = .roundedBezel;stretch(f,width);f.heightAnchor.constraint(equalToConstant:28).isActive=true }
    func row(_ title:String,_ control:NSView)->NSStackView { let l=label(title,dim:true);stretch(l,85);let r=stack([l,control],vertical:false);return r }
    func divider()->NSView { let v=NSView();v.wantsLayer=true;v.layer?.backgroundColor=Palette.border.cgColor;v.translatesAutoresizingMaskIntoConstraints=false;v.heightAnchor.constraint(equalToConstant:1).isActive=true;return v }
    func buildWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        if let screen=NSScreen.main { let available=screen.visibleFrame;window.setContentSize(NSSize(width:min(1180,available.width-60),height:min(820,available.height-80))) };window.title="Sous-titres FilmCraft"; window.minSize=NSSize(width:1080,height:740); window.delegate=self;window.center();window.backgroundColor=Palette.canvas
        let root=NSView(); root.wantsLayer=true;root.layer?.backgroundColor=Palette.canvas.cgColor;window.contentView=root
        openButton=button("Timeline FilmCraft",#selector(useTimeline));stretch(openButton,155)
        importButton=button("Importer SRT",#selector(importSRT));stretch(importButton,115)
        exportButton=button("Exporter…",#selector(exportSubtitles));stretch(exportButton,110)
        titleLabel.font = .systemFont(ofSize:13,weight:.medium);titleLabel.textColor=Palette.text;titleLabel.lineBreakMode = .byTruncatingMiddle;titleLabel.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let header=stack([openButton,titleLabel,importButton,exportButton],vertical:false,spacing:12)
        let headerPanel=NSView();headerPanel.wantsLayer=true;headerPanel.layer?.backgroundColor=Palette.chrome.cgColor;fill(header,in:headerPanel,inset:16)
        let content=NSView();let footer=NSView();footer.wantsLayer=true;footer.layer?.backgroundColor=Palette.chrome.cgColor
        let outer=stack([headerPanel,content,footer],spacing:0);fill(outer,in:root)
        for v in [headerPanel,content,footer] { v.widthAnchor.constraint(equalTo:outer.widthAnchor).isActive=true }
        headerPanel.heightAnchor.constraint(equalToConstant:64).isActive=true;footer.heightAnchor.constraint(equalToConstant:77).isActive=true
        let left=NSView();let rightScroll=NSScrollView();rightScroll.contentView=TopAlignedClipView();rightScroll.drawsBackground=false;rightScroll.hasVerticalScroller=true;rightScroll.scrollerStyle = .legacy;rightScroll.autohidesScrollers=false;stretch(rightScroll,330)
        let body=stack([left,divider(),rightScroll],vertical:false,spacing:18);fill(body,in:content,inset:20)
        // Stack's separator is vertical here.
        if let sep=body.arrangedSubviews.dropFirst().first { sep.removeConstraints(sep.constraints);sep.widthAnchor.constraint(equalToConstant:1).isActive=true;sep.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true }
        left.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true;rightScroll.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true
        let videoPanel=NSView();videoPanel.wantsLayer=true;videoPanel.layer?.backgroundColor=NSColor.black.cgColor
        playerView.player=player;playerView.controlsStyle = .none;playerView.videoGravity = .resizeAspect;fill(playerView,in:videoPanel);fill(overlay,in:videoPanel)
        videoPanel.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive=true
        let previewTitle=stack([section("Aperçu"),label("Style · FilmCraft et export ASS",dim:true,size:11)],vertical:false)
        let tableScroll=NSScrollView();tableScroll.hasVerticalScroller=true;tableScroll.drawsBackground=true;tableScroll.backgroundColor=Palette.field;tableScroll.borderType = .lineBorder
        for (id,title,width) in [("number","Nº",CGFloat(35)),("start","Début",CGFloat(100)),("end","Fin",CGFloat(100)),("text","Texte",CGFloat(400))] { let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=title;c.width=width;c.minWidth=id=="text" ? 160 : width;c.resizingMask=id=="text" ? .autoresizingMask : [];table.addTableColumn(c) }
        table.dataSource=self;table.delegate=self;table.rowHeight=35;table.backgroundColor=Palette.field;table.selectionHighlightStyle = .regular;table.allowsMultipleSelection=false;table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle;tableScroll.documentView=table;tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant:150).isActive=true
        countLabel.font = .systemFont(ofSize:13,weight:.semibold);countLabel.textColor=Palette.text
        let add=button("Ajouter",#selector(addCue));let split=button("Scinder",#selector(splitCue));let merge=button("Fusionner",#selector(mergeCue));let delete=button("Supprimer",#selector(deleteCue));for b in [add,split,merge,delete] { stretch(b,85);b.setContentCompressionResistancePriority(.required,for:.horizontal) };editingControls += [add,split,merge,delete]
        let cueTools=stack([countLabel,NSView(),add,split,merge,delete],vertical:false,spacing:6)
        let play=button("▶  /  Ⅱ",#selector(togglePlayback));stretch(play,65);seekSlider.target=self;seekSlider.action=#selector(seekVideo);seekSlider.isContinuous=true;playbackTime.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);playbackTime.textColor=Palette.dim;stretch(playbackTime,112);let playback=stack([play,seekSlider,playbackTime],vertical:false,spacing:10)
        let leftStack=stack([previewTitle,videoPanel,playback,cueTools,tableScroll],spacing:10);fill(leftStack,in:left)
        for v in [previewTitle,videoPanel,playback,cueTools,tableScroll] { v.widthAnchor.constraint(equalTo:leftStack.widthAnchor).isActive=true }
        videoPanel.heightAnchor.constraint(equalTo:tableScroll.heightAnchor,multiplier:1.25).isActive=true
        let inspectorStack=makeInspector();inspector=inspectorStack;rightScroll.documentView=inspectorStack;inspectorStack.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([inspectorStack.widthAnchor.constraint(equalTo:rightScroll.contentView.widthAnchor,constant:-10),inspectorStack.leadingAnchor.constraint(equalTo:rightScroll.contentView.leadingAnchor),inspectorStack.topAnchor.constraint(equalTo:rightScroll.contentView.topAnchor)])
        transcribeButton=button("Transcrire la séquence",#selector(transcribe),primary:true);stretch(transcribeButton,185)
        subtitleButton=button("Sous-titrer la TL",#selector(sendFilmCraft),primary:true);stretch(subtitleButton,170)
        cancelButton=button("Annuler",#selector(cancel));stretch(cancelButton,85);cancelButton.isHidden=true
        progress.style = .bar;progress.isIndeterminate=true;progress.controlSize = .small;progress.minValue=0;progress.maxValue=1
        status.font = .systemFont(ofSize:12);status.textColor=Palette.dim;status.lineBreakMode = .byTruncatingTail;status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        elapsed.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);elapsed.textColor=Palette.dim
        let statrow=stack([status,NSView(),elapsed],vertical:false)
        let loading=stack([statrow,progress],spacing:8);for v in [statrow,progress] { v.widthAnchor.constraint(equalTo:loading.widthAnchor).isActive=true }
        let footerRow=stack([loading,cancelButton,transcribeButton,subtitleButton],vertical:false,spacing:14);fill(footerRow,in:footer,inset:18)
        progress.isHidden=true
    }
    func makeInspector()->NSStackView {
        field(startField);field(endField)
        let times=stack([stack([label("Début",dim:true),startField],spacing:5),stack([label("Fin",dim:true),endField],spacing:5)],vertical:false)
        times.distribution = .fillEqually
        textEditor.font = .systemFont(ofSize:13);textEditor.backgroundColor=Palette.field;textEditor.textColor=Palette.text;textEditor.isRichText=false;textEditor.allowsUndo=true;textEditor.isAutomaticQuoteSubstitutionEnabled=false;textEditor.isAutomaticDashSubstitutionEnabled=false;textEditor.textContainerInset=NSSize(width:8,height:8);textEditor.isVerticallyResizable=true;textEditor.autoresizingMask = [.width];textEditor.textContainer?.widthTracksTextView=true
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .lineBorder;scroll.documentView=textEditor;scroll.heightAnchor.constraint(equalToConstant:92).isActive=true
        let apply=button("Appliquer au sous-titre",#selector(applyCue));editingControls += [startField,endField,apply]
        let jump=button("Lire ce passage",#selector(playCue));editingControls.append(jump)
        let editActions=stack([jump,apply],vertical:false,spacing:6);editActions.distribution = .fillEqually
        lineChoice.addItems(withTitles:["Une ligne","Deux lignes"]);lineChoice.selectItem(at:1)
        field(maxCharsField,width:66);field(maxDurationField,width:66)
        let layoutHelp=NSTextField(wrappingLabelWithString:"Recompose le texte et répartit les temps proportionnellement. Relisez le minutage après modification.");layoutHelp.font = .systemFont(ofSize:11);layoutHelp.textColor=Palette.dim
        let reflow=button("Recomposer les sous-titres",#selector(reflow));editingControls.append(reflow)
        refreshFonts()
        fontChoice.target=self;fontChoice.action=#selector(fontFamilyChanged)
        faceChoice.target=self;faceChoice.action=#selector(styleChanged)
        field(outlineField,width:66)
        for c in [sizeSlider,xSlider,ySlider] {c.target=self;c.action=#selector(styleChanged);c.isContinuous=true}
        for well in [colorWell,outlineColorWell] {well.target=self;well.action=#selector(styleChanged);stretch(well,50);well.heightAnchor.constraint(equalToConstant:26).isActive=true}
        outlineField.target=self;outlineField.action=#selector(styleChanged)
        editingControls += [fontChoice,faceChoice,sizeSlider,xSlider,ySlider,colorWell,outlineColorWell,outlineField,lineChoice,maxCharsField,maxDurationField]
        for c in [lineChoice,maxCharsField,maxDurationField] as [NSControl] {c.target=self;c.action=#selector(layoutChanged)}
        faceRow=row("Variante",faceChoice)
        func sliderRow(_ title:String,_ slider:NSSlider,_ value:NSTextField)->NSStackView {
            value.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);value.textColor=Palette.dim;stretch(value,48)
            let controls=stack([slider,value],vertical:false,spacing:8);return row(title,controls)
        }
        let all:[NSView]=[section("Découpage"),row("Lignes",lineChoice),row("Caractères",maxCharsField),row("Durée max. (s)",maxDurationField),reflow,layoutHelp,divider(),section("Style"),row("Police",fontChoice),faceRow,sliderRow("Taille",sizeSlider,sizeValue),row("Texte",colorWell),row("Épaisseur · px",outlineField),row("Contour",outlineColorWell),divider(),section("Position"),sliderRow("Horizontal",xSlider,xValue),sliderRow("Vertical",ySlider,yValue)]
        let s=stack(all,spacing:10);for v in all { v.widthAnchor.constraint(equalTo:s.widthAnchor).isActive=true };return s
    }
    func numberOfRows(in tableView:NSTableView)->Int { project.segments.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard project.segments.indices.contains(row) else { return nil };let cue=project.segments[row]
        let f=NSTextField(labelWithString:"");f.lineBreakMode = .byTruncatingTail;f.textColor=Palette.text;f.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular)
        switch tableColumn?.identifier.rawValue { case "number":f.stringValue="\(row+1)";case "start":f.stringValue=SubtitleFormat.timestamp(cue.start);case "end":f.stringValue=SubtitleFormat.timestamp(cue.end);default:f.stringValue=cue.text.replacingOccurrences(of:"\n",with:"  ↵  ");f.font = .systemFont(ofSize:12) };if tableColumn?.identifier.rawValue != "number" {f.isEditable=true;f.isSelectable=true;f.delegate=self;f.tag=row;f.identifier=tableColumn?.identifier};return f
    }
    func controlTextDidEndEditing(_ notification:Notification) {
        guard let field=notification.object as? NSTextField,field.superview != nil,project.segments.indices.contains(field.tag),["text","start","end"].contains(field.identifier?.rawValue ?? "") else{return}
        var cues=project.segments;let i=field.tag
        switch field.identifier?.rawValue {
        case "text":cues[i].text=field.stringValue;cues[i].words=[]
        case "start":guard let t=SubtitleFormat.parseTime(field.stringValue) else{updateUI(select:i);return};cues[i].start=t;cues[i].words=[]
        case "end":guard let t=SubtitleFormat.parseTime(field.stringValue) else{updateUI(select:i);return};cues[i].end=t;cues[i].words=[]
        default:return
        }
        do {try SubtitleFormat.validate(cues);record();project.segments=cues;updateUI(select:i)}catch{show(error);updateUI(select:i)}
    }
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int)->Bool { !busy && commitCue() }
    func tableViewSelectionDidChange(_ notification:Notification) { loadCue();updateOverlay() }
    func loadCue() {
        guard let i=selected else { startField.stringValue="";endField.stringValue="";textEditor.string="";editorOriginal="";startOriginal="";endOriginal="";return }
        let c=project.segments[i];startField.stringValue=SubtitleFormat.timestamp(c.start);endField.stringValue=SubtitleFormat.timestamp(c.end);textEditor.string=c.text;editorOriginal=c.text;startOriginal=startField.stringValue;endOriginal=endField.stringValue
    }
    func record() { undoStates.append(project); if undoStates.count>100 {undoStates.removeFirst()};redoStates.removeAll() }
    @discardableResult func commitCue()->Bool {
        guard !updating,let i=selected else { return true }
        guard textEditor.string != editorOriginal || startField.stringValue != startOriginal || endField.stringValue != endOriginal else { return true }
        guard let start=SubtitleFormat.parseTime(startField.stringValue),let end=SubtitleFormat.parseTime(endField.stringValue) else { alert("Minutage invalide", "Utilisez hh:mm:ss,mmm ou un nombre de secondes.");return false }
        var cues=project.segments;cues[i].start=start;cues[i].end=end;cues[i].text=textEditor.string.trimmingCharacters(in:.whitespacesAndNewlines);cues[i].words=[]
        do {try SubtitleFormat.validate(cues)} catch {show(error);return false};record();project.segments=cues;table.reloadData();table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);loadCue();updateOverlay();markDirty();return true
    }
    @objc func applyCue() { _=commitCue() }
    func markDirty() {window.isDocumentEdited=false}
    func updateUI(select index:Int?=nil) {
        updating=true;defer{updating=false}
        titleLabel.stringValue=timelineMode ? (timelineTarget ?? liveTimeline).map { "\($0.projectName) · \($0.sequenceName)" } ?? "FilmCraft · connexion en attente" : (project.videoPath.isEmpty ? "Aucune vidéo" : URL(fileURLWithPath:project.videoPath).lastPathComponent)
        titleLabel.toolTip=project.videoPath
        countLabel.stringValue="\(project.segments.count) sous-titres"
        table.reloadData();if let i=index,project.segments.indices.contains(i){table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false)};loadCue()
        lineChoice.selectItem(at:project.lines-1);maxCharsField.integerValue=project.maxChars;maxDurationField.doubleValue=project.maxDuration
        fontChoice.selectItem(withTitle:project.style.fontFamily);refreshFaces(preserve:project.style.fontName)
        sizeSlider.doubleValue=project.style.fontSize;xSlider.doubleValue=project.style.positionX*100;ySlider.doubleValue=project.style.positionY*100
        sizeValue.stringValue="\(Int(project.style.fontSize)) px";xValue.stringValue="\(Int(xSlider.doubleValue)) %";yValue.stringValue="\(Int(ySlider.doubleValue)) %"
        outlineField.doubleValue=project.style.outline;colorWell.color=NSColor(hex:project.style.color);outlineColorWell.color=NSColor(hex:project.style.outlineColor)
        contextField.stringValue=project.context;offsetField.doubleValue=project.timelineOffset
        transcribeButton.title=timelineMode ? "Transcrire la séquence" : "Transcrire le fichier"
        transcribeButton.isEnabled = !busy;subtitleButton.isHidden=project.segments.isEmpty;subtitleButton.isEnabled = !busy && !project.segments.isEmpty && timelineTarget != nil
        transcribeButton.primary=project.segments.isEmpty;transcribeButton.needsDisplay=true
        exportButton.isEnabled = !busy && !project.segments.isEmpty;importButton.isEnabled = !busy;openButton.isEnabled = !busy

        for c in editingControls {c.isEnabled = !busy};offsetField.isEnabled = !busy && !timelineMode;textEditor.isEditable = !busy;cancelButton.isHidden = !busy;cancelButton.isEnabled = busy
        updateOverlay();markDirty()
    }
    func updateOverlay() {
        let t=player.currentTime().seconds
        if t.isFinite {seekSlider.maxValue=max(1,project.duration);seekSlider.doubleValue=t;func clock(_ time:Double)->String {let seconds=max(0,Int(time));return String(format:"%02d:%02d",seconds/60,seconds%60)};playbackTime.stringValue="\(clock(t)) / \(clock(project.duration))"}
        overlay.text=project.segments.first(where:{$0.start<=t && t<$0.end})?.text ?? ""
        if previewMode && project.videoPath.isEmpty {overlay.text=project.segments.first?.text ?? ""}
        overlay.style=project.style
        if let size=player.currentItem?.presentationSize,size.width>0,size.height>0 {overlay.videoSize=size}
    }
    @objc func undoEdit() { guard !busy else{return}; if let responder=window.firstResponder as? NSTextView,responder.undoManager?.canUndo == true,responder === textEditor {responder.undoManager?.undo();return};guard let state=undoStates.popLast() else{return};redoStates.append(project);project=state;updateUI() }
    @objc func redoEdit() {guard !busy,let state=redoStates.popLast() else{return};undoStates.append(project);project=state;updateUI()}
    @objc func layoutChanged() {guard !updating else{return};guard let chars=Int(maxCharsField.stringValue),(20...80).contains(chars),let duration=Double(maxDurationField.stringValue),(1...20).contains(duration) else{alert("Découpage invalide","Choisissez 20 à 80 caractères par ligne et une durée de 1 à 20 secondes.");updateUI();return};record();project.lines=lineChoice.indexOfSelectedItem+1;project.maxChars=chars;project.maxDuration=duration;markDirty()}
    @objc func contextChanged() {guard project.context != contextField.stringValue else{return};record();project.context=contextField.stringValue;markDirty()}
    func refreshFonts() {
        let selected=fontChoice.titleOfSelectedItem ?? project.style.fontFamily
        fontChoice.removeAllItems();fontChoice.addItems(withTitles:NSFontManager.shared.availableFontFamilies.sorted{$0.localizedStandardCompare($1) == .orderedAscending});fontChoice.selectItem(withTitle:selected)
    }
    func refreshFaces(preserve:String?=nil) {
        let family=fontChoice.titleOfSelectedItem ?? "Helvetica Neue"
        fontFaces=(NSFontManager.shared.availableMembers(ofFontFamily:family) ?? []).compactMap { member in
            guard member.count>1,let name=member[0] as? String,let style=member[1] as? String else{return nil};return (name,style)
        }
        faceChoice.removeAllItems();faceChoice.addItems(withTitles:fontFaces.map(\.style))
        if let selected=preserve.flatMap({name in fontFaces.firstIndex{$0.name==name}}){faceChoice.selectItem(at:selected)}
        else if let regular=fontFaces.firstIndex(where:{["Regular","Normal","Roman","Book"].contains($0.style)}){faceChoice.selectItem(at:regular)}
        faceRow?.isHidden=fontFaces.count<2
    }
    @objc func fontFamilyChanged() {refreshFaces();styleChanged()}
    @objc func styleChanged() {
        guard !updating else{return}
        guard let outline=Double(outlineField.stringValue),(0...10).contains(outline) else {alert("Contour invalide","Choisissez une épaisseur entre 0 et 10 px.");updateUI();return}
        record();project.style.fontFamily=fontChoice.titleOfSelectedItem ?? "Helvetica Neue"
        if fontFaces.indices.contains(faceChoice.indexOfSelectedItem){let face=fontFaces[faceChoice.indexOfSelectedItem];project.style.fontName=face.name;project.style.fontFace=face.style}
        project.style.fontSize=sizeSlider.doubleValue.rounded();project.style.outline=outline;project.style.color=colorWell.color.rgbHex;project.style.outlineColor=outlineColorWell.color.rgbHex
        project.style.positionX=xSlider.doubleValue/100;project.style.positionY=ySlider.doubleValue/100;project.style.bold=false
        sizeValue.stringValue="\(Int(project.style.fontSize)) px";xValue.stringValue="\(Int(xSlider.doubleValue)) %";yValue.stringValue="\(Int(ySlider.doubleValue)) %";updateOverlay();markDirty()
    }
    @objc func reflow() {guard !busy,commitCue(),!project.segments.isEmpty else{return};layoutChanged();record();project.segments=SubtitleFormat.reflow(project.segments,lines:project.lines,maxChars:project.maxChars,maxDuration:project.maxDuration);updateUI(select:0);status.stringValue="Découpage recomposé. Vérifiez la synchronisation à l’écoute."}
    @objc func togglePlayback() {if player.rate>0 {player.pause()}else{player.play()}}
    @objc func seekVideo() {player.seek(to:CMTime(seconds:seekSlider.doubleValue,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)}
    @objc func playCue() {guard commitCue(),let i=selected else{return};player.seek(to:CMTime(seconds:project.segments[i].start,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero);player.play()}
    @objc func addCue() {
        guard !busy,commitCue() else{return}
        let i=selected.map{$0+1} ?? project.segments.count
        let start=i>0 ? project.segments[i-1].end : 0
        let limit=i<project.segments.count ? project.segments[i].start : max(project.duration,start+2)
        guard limit-start>=0.05 else{alert("Pas d’espace disponible","Raccourcissez les sous-titres voisins avant d’ajouter un passage ici.");return};record();project.segments.insert(SubtitleCue(start:start,end:min(start+2,limit),text:"Nouveau sous-titre"),at:i);updateUI(select:i)
    }
    @objc func deleteCue() {guard !busy,commitCue(),let i=selected else{return};record();project.segments.remove(at:i);updateUI(select:min(i,project.segments.count-1))}
    @objc func splitCue() {
        guard !busy,commitCue(),let i=selected else{return};let cue=project.segments[i];let words=cue.text.split(whereSeparator:{$0.isWhitespace});guard words.count>1 else{alert("Impossible de scinder","Ce sous-titre doit contenir au moins deux mots.");return}
        let middle=words.count/2;let left=words.prefix(middle).joined(separator:" ");let right=words.dropFirst(middle).joined(separator:" ");let position=player.currentTime().seconds
        let time=position>cue.start+0.05 && position<cue.end-0.05 ? position : cue.start+(cue.end-cue.start)*Double(middle)/Double(words.count)
        record();project.segments.replaceSubrange(i...i,with:[SubtitleCue(start:cue.start,end:time,text:left),SubtitleCue(start:time,end:cue.end,text:right)]);updateUI(select:i);status.stringValue="Passage scindé au curseur vidéo ou au milieu du texte. Vérifiez l’écoute."
    }
    @objc func mergeCue() {guard !busy,commitCue(),let i=selected,i+1<project.segments.count else{return};let a=project.segments[i],b=project.segments[i+1];record();project.segments.replaceSubrange(i...i+1,with:[SubtitleCue(start:a.start,end:b.end,text:a.text.replacingOccurrences(of:"\n",with:" ")+" "+b.text.replacingOccurrences(of:"\n",with:" "))]);updateUI(select:i)}
    func alert(_ title:String,_ message:String) {let a=NSAlert();a.messageText=title;a.informativeText=message;a.runModal()}
    func show(_ error:Error) {if CommandLine.arguments.contains("--qa-timeline"){fputs("\(error.localizedDescription)\n",stderr);exit(1)};alert("Action à vérifier",error.localizedDescription)}
    @objc func openVideo() {
        guard !busy else{return};let p=NSOpenPanel();p.allowedContentTypes=[.movie,.audio];p.message="Choisissez la vidéo à transcrire. Le fichier original reste inchangé.";guard p.runModal() == .OK,let url=p.url else{return}
        timelineMode=false;timelineTarget=nil;automaticTransfer=false;project=SubtitleProject();project.videoPath=url.path;savedProject=project;projectURL=nil;undoStates=[];redoStates=[];loadVideo(url);updateUI();status.stringValue="Prêt · français · Whisper large-v3 · traitement local."
    }
    func loadVideo(_ url:URL) {
        player.pause();let asset=AVURLAsset(url:url);let item=AVPlayerItem(asset:asset);player.replaceCurrentItem(with:item)
        Task {do {let duration=try await asset.load(.duration);let playable=try await asset.load(.isPlayable);await MainActor.run {guard self.project.videoPath==url.path else{return};if duration.seconds.isFinite {self.project.duration=duration.seconds; if self.savedProject.segments.isEmpty {self.savedProject.duration=duration.seconds} };if !playable {self.status.stringValue="L’aperçu ne lit pas ce format. Whisper peut tout de même tenter la transcription."}}}catch{await MainActor.run {self.status.stringValue="Aperçu indisponible pour ce fichier. La transcription peut être tentée."}}}
    }
    @objc func importSRT() {
        guard !busy,commitCue() else{return}
        if !project.segments.isEmpty {let a=NSAlert();a.messageText="Remplacer les sous-titres actuels ?";a.informativeText="L’import conserve la vidéo et le style. Vous pourrez annuler cette opération.";a.addButton(withTitle:"Importer");a.addButton(withTitle:"Annuler");guard a.runModal() == .alertFirstButtonReturn else{return}}
        let p=NSOpenPanel();p.allowedContentTypes=[UTType(filenameExtension:"srt") ?? .plainText];guard p.runModal() == .OK,let url=p.url else{return}
        do {let data=try Data(contentsOf:url);guard data.count<50_000_000,let raw=String(data:data,encoding:.utf8) else{throw SubtitleError.invalid("Importez un SRT en UTF-8 de moins de 50 Mo.")};let cues=try SubtitleFormat.importSRT(raw);record();project.segments=cues;updateUI(select:0);status.stringValue="SRT importé. Les temps sont relatifs au début de la vidéo."}catch{show(error)}
    }
    @objc func exportSubtitles() {
        guard !busy,commitCue(),!project.segments.isEmpty else{return};let p=NSSavePanel();p.allowedContentTypes=[UTType(filenameExtension:"srt") ?? .plainText,UTType(filenameExtension:"vtt") ?? .plainText,UTType(filenameExtension:"ass") ?? .plainText];p.nameFieldStringValue="Sous-titres.srt";p.message="SRT et VTT : texte et minutage. ASS : texte, minutage et style."
        let format=NSPopUpButton();format.addItems(withTitles:["SRT · FilmCraft et monteurs vidéo","VTT · web","ASS · style complet"]);let accessories=stack([label("Format"),format],spacing:6);p.accessoryView=accessories;p.isExtensionHidden=false
        guard p.runModal() == .OK,let requested=p.url else{return};let ext=["srt","vtt","ass"][format.indexOfSelectedItem];let url=requested.deletingPathExtension().appendingPathExtension(ext)
        // Changing formats after entering a name can target a different existing file.
        if url != requested,FileManager.default.fileExists(atPath:url.path){let a=NSAlert();a.messageText="Remplacer \(url.lastPathComponent) ?";a.addButton(withTitle:"Remplacer");a.addButton(withTitle:"Annuler");guard a.runModal() == .alertFirstButtonReturn else{return}}
        do {let raw:String;switch ext{case "ass":raw=try SubtitleFormat.ass(exportCues(),style:project.style);case "vtt":raw=try SubtitleFormat.vtt(exportCues());default:raw=try SubtitleFormat.srt(exportCues())};try raw.write(to:url,atomically:true,encoding:.utf8);status.stringValue="\(url.lastPathComponent) exporté.";NSWorkspace.shared.activateFileViewerSelecting([url])}catch{show(error)}
    }
    @objc func transcribe() {
        if timelineMode && !busy { transcribeTimeline();return }
        transcribeMedia()
    }
    func transcribeMedia() {
        guard !busy,!project.videoPath.isEmpty,commitCue() else{return};contextChanged();layoutChanged()

        guard let engine=Bundle.main.resourceURL?.appendingPathComponent("bin/transcribe"),FileManager.default.isExecutableFile(atPath:engine.path) else{alert("Moteur absent","Réinstallez l’application complète pour retrouver le moteur de transcription.");return}
        let job=UUID();let directory=FileManager.default.temporaryDirectory.appendingPathComponent("artcraft-subtitles-\(job.uuidString)",isDirectory:true)
        do {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}catch{show(error);return}
        let output=directory.appendingPathComponent("transcription.json");let p=Process();p.executableURL=engine;p.arguments=["--input",project.videoPath,"--output",output.path,"--context",project.context,"--lines",String(project.lines),"--max-chars",String(project.maxChars),"--max-duration",String(project.maxDuration)]
        let out=Pipe(),err=Pipe();p.standardOutput=out;p.standardError=err;progressPipe=out;stderrPipe=err;task=p;processBuffer=Data();errorBuffer=Data();currentTaskID=job;cancelled=false
        out.fileHandleForReading.readabilityHandler={ [weak self] handle in
            let data=handle.availableData;guard !data.isEmpty,let self=self else{return};self.pipeLock.lock();self.processBuffer.append(data);var messages:[Data]=[];while let newline=self.processBuffer.firstIndex(of:10){messages.append(self.processBuffer.prefix(upTo:newline));self.processBuffer.removeSubrange(...newline)};self.pipeLock.unlock()
            for line in messages {guard let object=try? JSONSerialization.jsonObject(with:line) as? [String:Any] else{continue};DispatchQueue.main.async {guard self.currentTaskID==job else{return};if let message=object["message"] as? String{self.status.stringValue=message};if let value=object["progress"] as? Double,value.isFinite {self.progress.isIndeterminate=false;self.progress.doubleValue=max(0,min(1,value))}else{self.progress.isIndeterminate=true;self.progress.startAnimation(nil)}}}
        }
        err.fileHandleForReading.readabilityHandler={ [weak self] handle in let data=handle.availableData;guard let self=self else{return};self.pipeLock.lock();if self.errorBuffer.count<32_000 {self.errorBuffer.append(data.prefix(32_000-self.errorBuffer.count))};self.pipeLock.unlock() }
        p.terminationHandler={ [weak self] process in
            out.fileHandleForReading.readabilityHandler=nil;err.fileHandleForReading.readabilityHandler=nil
            DispatchQueue.main.async {guard let self=self,self.currentTaskID==job else{return};defer{try? FileManager.default.removeItem(at:directory)};self.task=nil;self.currentTaskID=nil;self.timer?.invalidate();self.timer=nil;self.busy=false;self.progress.stopAnimation(nil);self.progress.isIndeterminate=false;self.progress.isHidden=true;self.progressPipe=nil;self.stderrPipe=nil
                if self.cancelled {self.restoreTimelineAfterFailure();self.status.stringValue="Transcription annulée. Vos sous-titres sont conservés.";self.updateUI();return}
                do {guard process.terminationStatus==0 else {self.pipeLock.lock();let detail=String(data:self.errorBuffer,encoding:.utf8) ?? "";self.pipeLock.unlock();throw SubtitleError.invalid(detail.isEmpty ? "La transcription n’a pas abouti. Vérifiez que la vidéo contient une piste audio lisible." : String(detail.suffix(4000)))}
                    let decoded=try JSONDecoder().decode(TranscriptionResult.self,from:Data(contentsOf:output));try SubtitleFormat.validate(decoded.segments);self.record();self.project.segments=decoded.segments;if let duration=decoded.duration,duration.isFinite,duration>=0{self.project.duration=duration};if let model=decoded.model{self.project.model=model};self.timelinePreviousState=nil;self.updateUI(select:0);self.status.stringValue=decoded.segments.isEmpty ? "Aucune parole détectée. Vérifiez la piste audio." : "Transcription prête · ajustez le texte et le style, puis cliquez « Sous-titrer la TL ».";if CommandLine.arguments.contains("--qa-timeline") {self.finishTimelineTranscriptionQA()}else{self.finishQA()}
                }catch{self.restoreTimelineAfterFailure();self.status.stringValue="La transcription n’a pas abouti.";self.updateUI();if CommandLine.arguments.contains("--qa-video"){fputs("\(error.localizedDescription)\n",stderr);exit(1)};self.show(error)}
            }
        }
        do {try p.run();busy=true;player.pause();startedAt=Date();progress.isHidden=false;progress.isIndeterminate=true;progress.startAnimation(nil);status.stringValue="Préparation de la transcription…";timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in guard let self=self,let start=self.startedAt else{return};let secs=Int(Date().timeIntervalSince(start));self.elapsed.stringValue=String(format:"Temps écoulé · %02d:%02d",secs/60,secs%60)};updateUI()}
        catch{out.fileHandleForReading.readabilityHandler=nil;err.fileHandleForReading.readabilityHandler=nil;task=nil;currentTaskID=nil;try? FileManager.default.removeItem(at:directory);restoreTimelineAfterFailure();updateUI();show(error)}
    }
    @objc func cancel() {if let token=timelineExportCancellation {token.cancel();cancelButton.isEnabled=false;status.stringValue="Annulation du mixage…";return};guard let task=task,busy else{return};cancelled=true;cancelButton.isEnabled=false;status.stringValue="Annulation du calcul…";task.terminate()}

    @objc func offsetChanged() {
        guard let value=Double(offsetField.stringValue),value.isFinite,value>=0,value<864_000 else{alert("Décalage invalide","Indiquez un nombre de secondes positif, inférieur à 10 jours.");offsetField.doubleValue=project.timelineOffset;return}
        guard value != project.timelineOffset else{return};record();project.timelineOffset=value;markDirty()
    }
    func exportCues()->[SubtitleCue] { project.exportSegments }
    @objc func openFilmCraft() {
        #if FILMCRAFT_INTEGRATION
        FilmCraftBridge.shared.openFilmCraft { result in if case .failure(let error)=result {self.show(error)} }
        #else
        alert("FilmCraft", "Exportez un SRT, puis importez-le dans FilmCraft.")
        #endif
    }
    @objc func sendFilmCraft() {
        guard !busy,commitCue(),!project.segments.isEmpty else{return}
        #if FILMCRAFT_INTEGRATION
        if timelineMode, timelineTarget != nil {transferBoundTimeline();return}
        let bridge=FilmCraftBridge.shared
        DispatchQueue.global(qos:.userInitiated).async {
            do {let context=try bridge.snapshot();DispatchQueue.main.async {
                let a=NSAlert();a.messageText="Envoyer vers « \(context.sequenceName) » ?";a.informativeText="Projet : \(context.projectName)\n\(self.project.segments.count) sous-titres · décalage : \(self.project.timelineOffset) s\nUne nouvelle piste de sous-titres sera ajoutée dans la séquence active.";a.addButton(withTitle:"Envoyer");a.addButton(withTitle:"Annuler");guard a.runModal()  == .alertFirstButtonReturn else{return}
                do {let raw=try SubtitleFormat.srt(self.exportCues());let temp=FileManager.default.temporaryDirectory.appendingPathComponent("ArtCraft-Captions-\(UUID().uuidString).srt");try raw.write(to:temp,atomically:true,encoding:.utf8)
                    let style=SubtitleFilmCraftAdapter.style(self.project.style)
                    self.busy=true;self.status.stringValue="Envoi des sous-titres vers FilmCraft…";self.updateUI();self.cancelButton.isHidden=true
                    DispatchQueue.global(qos:.userInitiated).async {do {let result=try bridge.importCaptions(srtURL:temp,style:style,expected:context);DispatchQueue.main.async {self.busy=false;self.status.stringValue=result.message;self.updateUI()}}catch{DispatchQueue.main.async{self.busy=false;self.updateUI();if CommandLine.arguments.contains("--qa-video"){fputs("\(error.localizedDescription)\n",stderr);exit(1)};self.show(error)}};try? FileManager.default.removeItem(at:temp)}
                }catch{self.show(error)}
            }}catch{DispatchQueue.main.async{self.show(error)}}
        }
        #else
        alert("FilmCraft", "Exportez un SRT, puis importez-le dans FilmCraft.")
        #endif
    }


    // Explicit fixture-only automation exercises the same controller actions as the UI.
    func runQAEditChecks(outputURL: URL) throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw SubtitleError.invalid("QA édition : " + message) }
        }
        guard let first = project.segments.first else { throw SubtitleError.invalid("QA édition : aucune parole transcrite.") }
        let initialCount = project.segments.count
        updateUI(select: 0)
        let correction = "Correction manuelle : Élodie à Paris, avec FilmCraft."
        textEditor.string = correction
        let inset = min(0.02, (first.end - first.start) / 10)
        startField.stringValue = SubtitleFormat.timestamp(first.start + inset)
        endField.stringValue = SubtitleFormat.timestamp(first.end - inset)
        applyCue()
        try check(project.segments[0].text == correction, "texte corrigé conservé")
        try check(abs(project.segments[0].start - (first.start + inset)) <= 0.001, "début corrigé")
        try check(abs(project.segments[0].end - (first.end - inset)) <= 0.001, "fin corrigée")
        splitCue()
        try check(project.segments.count == initialCount + 1, "scission")
        let splitState = project
        mergeCue()
        try check(project.segments.count == initialCount, "fusion")
        try check(project.segments[0].text == correction, "fusion conserve les accents et tous les mots")
        let mergedState = project
        window.makeFirstResponder(table)
        undoEdit()
        try check(project == splitState, "annuler la fusion")
        redoEdit()
        try check(project == mergedState, "rétablir la fusion")
        let data = try JSONEncoder().encode(project)
        let reopened = try JSONDecoder().decode(SubtitleProject.self, from: data).validated()
        try check(reopened == project, "projet rouvert conserve corrections, contexte et style")
        let base = outputURL.deletingPathExtension()
        let cues = project.exportSegments
        let srt = try SubtitleFormat.srt(cues)
        let vtt = try SubtitleFormat.vtt(cues)
        let ass = try SubtitleFormat.ass(cues, style: project.style)
        try check(srt.contains(correction) && vtt.contains(correction) && ass.contains(correction), "trois exports conservent la correction")
        let imported = try SubtitleFormat.importSRT(srt)
        try check(imported.first?.text == correction, "SRT réimporté conserve la correction")
        try srt.write(to: base.appendingPathExtension("srt"), atomically: true, encoding: .utf8)
        try vtt.write(to: base.appendingPathExtension("vtt"), atomically: true, encoding: .utf8)
        try ass.write(to: base.appendingPathExtension("ass"), atomically: true, encoding: .utf8)
        let report = "Controller editing checks passed: manual French text, start/end, apply, split, merge, undo, redo, project roundtrip, SRT/VTT/ASS exports and SRT reimport.\n"
        try report.write(to: base.appendingPathExtension("editing-checks.txt"), atomically: true, encoding: .utf8)
        print(report)
        updateUI(select: 0)
    }

    func finishQA() {
        guard let index=CommandLine.arguments.firstIndex(of:"--qa-output"),index+1<CommandLine.arguments.count else{return}
        let path=CommandLine.arguments[index+1]
        do {if CommandLine.arguments.contains("--qa-edit-checks"){try runQAEditChecks(outputURL:URL(fileURLWithPath:path))};try JSONEncoder().encode(project).write(to:URL(fileURLWithPath:path),options:.atomic)}catch{fputs("\(error.localizedDescription)\n",stderr);exit(1)}
        savedProject=project
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4){if let view=self.window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path+".png"))};NSApp.terminate(nil)}
    }

    func checkStyleControls() throws {
        func check(_ value:Bool,_ message:String)throws {if !value{throw SubtitleError.invalid(message)}}
        let installed=Set(NSFontManager.shared.availableFontFamilies)
        try check(Set(fontChoice.itemTitles)==installed,"Toutes les familles doivent être disponibles")
        fontChoice.selectItem(withTitle:"Avenir Next");fontFamilyChanged()
        try check(fontFaces.count>1 && !faceRow.isHidden,"Les variantes doivent être visibles")
        if let index=fontFaces.firstIndex(where:{$0.style.localizedCaseInsensitiveContains("italic")}){faceChoice.selectItem(at:index)}
        sizeSlider.doubleValue=67;xSlider.doubleValue=27;ySlider.doubleValue=31
        outlineColorWell.color=NSColor(hex:"#ED7242");styleChanged()
        try check(project.style.fontName==fontFaces[faceChoice.indexOfSelectedItem].name,"Variante conservée")
        try check(project.style.fontSize==67 && project.style.positionX==0.27 && project.style.positionY==0.31,"Curseurs conservés")
        try check(project.style.outlineColor=="#ED7242","Couleur du contour conservée")
        try check(overlay.style==project.style,"Aperçu synchronisé")
        if let cell=table.view(atColumn:3,row:0,makeIfNecessary:true) as? NSTextField {
            cell.stringValue="Correction directe dans la liste."
            controlTextDidEndEditing(Notification(name:NSControl.textDidEndEditingNotification,object:cell))
            try check(project.segments.first?.text=="Correction directe dans la liste.","Édition directe dans la liste")
        }else{throw SubtitleError.invalid("Cellule éditable absente")}
        print("Style controls OK: \(installed.count) families, \(fontFaces.count) Avenir Next faces, size/X/Y sliders and outline color.")
        status.stringValue="Style testé · \(installed.count) familles de polices disponibles";updateUI(select:0)
    }

    func makePreview() {
        previewMode=true;playerView.isHidden=true;project.segments=[SubtitleCue(start:0,end:3.2,text:"Chaque voix raconte une histoire.\nÀ vous de lui donner forme."),SubtitleCue(start:3.3,end:6.8,text:"La transcription devient un point de départ."),SubtitleCue(start:7,end:10.4,text:"Relisez les mots, ajustez le rythme."),SubtitleCue(start:10.5,end:13.8,text:"Et retrouvez votre style dans FilmCraft.")];savedProject=project;updateUI(select:0);if let index=CommandLine.arguments.firstIndex(of:"--preview-video"),index+1<CommandLine.arguments.count {let video=URL(fileURLWithPath:CommandLine.arguments[index+1]);project.videoPath=video.path;savedProject=project;playerView.isHidden=false;loadVideo(video);player.seek(to:CMTime(seconds:1,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)};titleLabel.stringValue="Interview · exemple de sous-titres";status.stringValue="Français · Whisper large-v3 · traitement local"
        if CommandLine.arguments.contains("--qa-style-controls") {
            do {try checkStyleControls();finishQA()}catch{show(error);exit(1)};return
        }
        if CommandLine.arguments.contains("--qa-edit-checks") {finishQA();return}
        if let index=CommandLine.arguments.firstIndex(of:"--preview-output"),index+1<CommandLine.arguments.count {
            let path=CommandLine.arguments[index+1];DispatchQueue.main.asyncAfter(deadline:.now()+1.5){self.window.contentView?.layoutSubtreeIfNeeded();if let view=self.window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))};self.savedProject=self.project;NSApp.terminate(nil)}
        }
    }
}
@main enum Main {
    static func main() {if CommandLine.arguments.contains("--self-test") {do {try SubtitleSelfTest.run();print("Subtitle document tests: OK")}catch{fputs("Tests échoués : \(error.localizedDescription)\n",stderr);exit(1)};return};let app=NSApplication.shared;let delegate=SubtitleApp();app.delegate=delegate;withExtendedLifetime(delegate){app.run()} }
}
