import AppKit
import Foundation
@main enum AuthenticationFixture {
    static func main()throws {
        guard CommandLine.arguments.count==4,let pid=Int32(CommandLine.arguments[1]),let port=UInt16(CommandLine.arguments[2]),port != FilmCraftBridge.port,let token=ProcessInfo.processInfo.environment["FILMCRAFT_CONTROL_TOKEN"],FilmCraftSession.valid(token) else{fatalError("Explicit isolated PID, port, output directory and token environment required")}
        let bridge=FilmCraftBridge(connectionPort:port,hostPID:pid),target=try bridge.snapshot()
        guard target.projectPath==nil,target.sequenceName.hasPrefix("Format fixture authentication") else{fatalError("Not an isolated test sequence")}
        var rejected=false
        do{_=try FilmCraftConnection(port:port).execute("file.newSequence",["name":"Must not be created"])}catch FilmCraftBridgeError.authentication{rejected=true}
        guard rejected else{fatalError("Missing token was not classified as authentication failure")}
        var wrongRejected=false
        do{_=try FilmCraftConnection(port:port,token:String(repeating:"0",count:64)).execute("file.newSequence",["name":"Must not be created either"])}catch FilmCraftBridgeError.authentication{wrongRejected=true}
        guard wrongRejected,try bridge.snapshot()==target else{fatalError("Unauthenticated request changed the fixture")}
        let connection=try FilmCraftConnection(port:port,token:token)
        _=try connection.call("engine.commands");_=try connection.execute("project.inspect",[:])
        let cues=[FilmCraftCue(start:0,end:2,text:"Connexion sécurisée."),FilmCraftCue(start:2.2,end:4.8,text:"FilmCraft est prêt.")],style=SubtitleStyle()
        let first=try bridge.sendTitles(cues:cues,style:style,expected:target,binding:nil)
        let edited=[FilmCraftCue(start:0,end:2,text:"Correction conservée."),cues[1]]
        let second=try bridge.sendTitles(cues:edited,style:style,expected:first.context,binding:first.binding)
        guard first.binding.trackID==second.binding.trackID,second.binding.clips.count==2 else{fatalError("Track duplicated on update")}
        let audio=URL(fileURLWithPath:CommandLine.arguments[3]).appendingPathComponent("mixage.wav")
        let final=try bridge.exportTimeline(to:audio,expected:second.context,cancelled:{false},progress:{_ in})
        guard final==second.context,FileManager.default.fileExists(atPath:audio.path) else{fatalError("Audio export failed")}
        print("Authenticated connection: multiple requests, missing-token rejection, timeline detection, audio export, titles and same-track updates OK")
    }
}
