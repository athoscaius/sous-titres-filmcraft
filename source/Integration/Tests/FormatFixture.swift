import AppKit
@main struct FormatFixture {
    static func main() throws {
        guard CommandLine.arguments.count==3,let pid=Int32(CommandLine.arguments[1]),let port=UInt16(CommandLine.arguments[2]),port != FilmCraftBridge.port else{fatalError("Explicit isolated host PID and port required")}
        let bridge=FilmCraftBridge(connectionPort:port,hostPID:pid)
        let target=try bridge.snapshot()
        guard target.projectPath==nil,target.sequenceName.hasPrefix("Format fixture ") else{fatalError("Not an isolated format fixture")}
        var style=SubtitleStyle();style.outline=4
        let cues=[FilmCraftCue(start:0,end:2,text:"Bonjour à tous."),FilmCraftCue(start:2.2,end:4.8,text:"Une transcription française assez longue pour tester la largeur de cette séquence.")]
        let result=try bridge.sendTitles(cues:cues,style:style,lines:1,expected:target,binding:nil)
        let layouts=cues.map{SubtitleTextLayout.make(text:$0.text,style:style,canvas:target.canvas,lines:1)}
        let json:[String:Any]=["width":target.canvas.width,"height":target.canvas.height,"ratio":target.canvas.ratio,"clips":result.binding.clips,"fontSizes":layouts.map(\.fontSize),"positions":layouts.map{[$0.frame.midX,$0.baseline]}]
        print(String(data:try JSONSerialization.data(withJSONObject:json,options:.sortedKeys),encoding:.utf8)!)
    }
}
