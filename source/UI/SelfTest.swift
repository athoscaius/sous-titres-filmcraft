import Foundation
import AppKit

enum SubtitleSelfTest {
    static func tryOuterOutlineRendering() -> Bool {
        func render(outline:Double) -> NSBitmapImageRep {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:960,pixelsHigh:540,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let view=SubtitleOverlay(frame:NSRect(x:0,y:0,width:960,height:540))
            view.text="Éléonore · FilmCraft";view.style.fontSize=140
            view.style.outline=outline;view.style.outlineColor="#FF0000"
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        let plain=render(outline:0),outlined=render(outline:8)
        var fillPixels=0,exteriorPixels=0
        for y in 0..<540 {for x in 0..<960 {
            guard let a=plain.colorAt(x:x,y:y),let b=outlined.colorAt(x:x,y:y) else{return false}
            if a.alphaComponent>0.99 && min(a.redComponent,a.greenComponent,a.blueComponent)>0.99 {
                fillPixels += 1
                if min(b.redComponent,b.greenComponent,b.blueComponent)<0.95 {return false}
            }
            if a.alphaComponent<0.01 && b.alphaComponent>0.9 && b.redComponent>0.9 && b.greenComponent<0.1 {exteriorPixels += 1}
        }}
        return fillPixels>1000 && exteriorPixels>1000
    }
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool,_ name:String) throws {if !value(){throw SubtitleError.invalid(name)}}
        func rejects(_ name:String,_ body:() throws->Void) throws {var failed=false;do{try body()}catch{failed=true};try check(failed,name)}
        let defaults=SubtitleProject()
        try check(defaults.lines==1 && defaults.maxChars==35 && defaults.maxDuration==3,"Requested default segmentation")
        try check(defaults.style.fontFamily=="Delight" && defaults.style.fontFace=="Semi Bold" && defaults.style.fontSize==70 && defaults.style.outline==0,"Requested default typography")
        try check(tryOuterOutlineRendering(),"Outer outline preserves letter fill and adds exterior pixels")
        let formats=[SubtitleCanvas.fullHD,SubtitleCanvas(width:1080,height:1920),SubtitleCanvas(width:1080,height:1080),SubtitleCanvas(width:3840,height:2160),SubtitleCanvas(width:2160,height:3840),SubtitleCanvas(width:2560,height:1080)]
        let sample="Une transcription française assez longue pour tester l’adaptation automatique."
        for canvas in formats {
            let fitted=canvas.fitted(in:NSRect(x:0,y:0,width:700,height:320))
            try check(abs(fitted.width/fitted.height-canvas.ratio)<0.0001,"Preview keeps sequence aspect ratio")
            for lines in [1,2] {
                let layout=SubtitleTextLayout.make(text:sample,style:defaults.style,canvas:canvas,lines:lines)
                try check(layout.frame.minX>=0 && layout.frame.maxX<=canvas.width && layout.frame.minY>=0 && layout.frame.maxY<=canvas.height,"Adaptive captions remain inside sequence")
                try check(layout.text.components(separatedBy:"\n").count<=lines,"Adaptive captions respect selected line count")
                try check(layout.text.split(whereSeparator:{$0.isWhitespace})==sample.split(whereSeparator:{$0.isWhitespace}),"Adaptive layout preserves corrected words")
                let ass=try SubtitleFormat.ass([SubtitleCue(start:0,end:1,text:sample)],style:defaults.style,canvas:canvas,lines:lines)
                try check(ass.contains("PlayResX: \(Int(canvas.width))") && ass.contains("PlayResY: \(Int(canvas.height))"),"ASS uses actual sequence resolution")
            }
        }
        let portrait=SubtitleCanvas(width:1080,height:1920)
        let shortHD=SubtitleTextLayout.make(text:"Bonjour",style:defaults.style,canvas:.fullHD,lines:1)
        let short4K=SubtitleTextLayout.make(text:"Bonjour",style:defaults.style,canvas:SubtitleCanvas(width:3840,height:2160),lines:1)
        let shortVertical=SubtitleTextLayout.make(text:"Bonjour",style:defaults.style,canvas:portrait,lines:1)
        try check(shortHD.fontSize==70 && shortVertical.fontSize==70 && short4K.fontSize==140,"Short-side font scaling avoids oversized vertical titles")
        let vertical=SubtitleTextLayout.make(text:sample,style:defaults.style,canvas:portrait,lines:1)
        try check(vertical.fontSize<shortVertical.fontSize,"Long vertical captions shrink to fit one line")
        let par=try SubtitleCanvas.from(settings:["width":1440,"height":1080,"par":[4,3]])
        try check(abs(par.ratio-16.0/9)<0.00001,"Non-square pixels affect displayed aspect ratio")
        try rejects("Invalid sequence dimensions rejected"){_=try SubtitleCanvas.from(settings:["width":0,"height":1080])}
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(defaults)) as! [String:Any];legacy.removeValue(forKey:"canvas")
        let restoredLegacy=try JSONDecoder().decode(SubtitleProject.self,from:JSONSerialization.data(withJSONObject:legacy))
        try check(restoredLegacy.outputCanvas == .fullHD,"Older documents keep a valid fallback canvas")
        let cues=[SubtitleCue(start:0.125,end:3.75,text:"Bonjour, François.\nBienvenue à Paris."),SubtitleCue(start:4,end:6.9,text:"Voici le contexte : l’intelligence artificielle.")]
        let srt=try SubtitleFormat.srt(cues)
        try check(srt.contains("00:00:00,125 --> 00:00:03,750"),"SRT millisecond precision")
        let imported=try SubtitleFormat.importSRT(srt.replacingOccurrences(of:"\n",with:"\r\n"))
        try check(imported.map(\.text)==cues.map(\.text),"SRT UTF-8 multiline roundtrip")
        try check(imported.map(\.start)==cues.map(\.start),"SRT timing roundtrip")
        try check(SubtitleFormat.parseTime("01:02:03,456")==3723.456,"French time parser")
        try check(SubtitleFormat.parseTime("00:61:00")==nil,"Invalid minutes")
        try check(SubtitleFormat.parseTime("nan")==nil,"Reject NaN")
        try rejects("Overlap rejected"){try SubtitleFormat.validate([cues[0],SubtitleCue(start:3,end:4,text:"Chevauchement")])}
        try rejects("Empty text rejected"){try SubtitleFormat.validate([SubtitleCue(start:0,end:1,text:" ")])}
        try rejects("Negative time rejected"){try SubtitleFormat.validate([SubtitleCue(start:-1,end:1,text:"Non")])}
        try rejects("Reversed interval rejected"){try SubtitleFormat.validate([SubtitleCue(start:2,end:1,text:"Non")])}
        let escaped=[SubtitleCue(start:1,end:2,text:"A < B & C > D")]
        let vtt=try SubtitleFormat.vtt(escaped)
        try check(vtt.contains("A &lt; B &amp; C &gt; D"),"WebVTT escaped markup")
        var style=SubtitleStyle();style.color="#123456";style.top=true;style.fontSize=64;style.outline=2
        let ass=try SubtitleFormat.ass([SubtitleCue(start:1.235,end:3,text:"{\\bord100} texte\nDeuxième ligne")],style:style)
        try check(ass.contains("&H00563412"),"ASS BGR color")
        try check(ass.contains("1,2.0,0,8,80,80,70,1"),"ASS anchor + outline")
        try check(!ass.contains("{\\bord100}"),"ASS escaped controls")
        try check(ass.contains("\\NDeuxième ligne"),"ASS explicit line breaks")
        style.outlineColor="#A1B2C3";style.positionX=0.27;style.positionY=0.31
        let positionedASS=try SubtitleFormat.ass(cues,style:style)
        try check(positionedASS.contains("&H00C3B2A1"),"ASS outline color")
        try check(positionedASS.contains("\\pos(") && !positionedASS.contains("\\pos(960,540)"),"ASS free position")
        var p=SubtitleProject();p.videoPath="/tmp/Interview française.mov";p.duration=7;p.style=style;p.segments=cues;p.context="François, Paris";p.timelineOffset=12.5
        let restored=try JSONDecoder().decode(SubtitleProject.self,from:JSONEncoder().encode(p)).validated()
        try check(restored==p,"Project source style and transcript roundtrip")
        var bad=p;bad.style.fontSize = -4
        try rejects("Project invalid style rejected"){_=try bad.validated()}
        let long=SubtitleCue(start:1,end:11,text:"Une transcription suffisamment longue pour vérifier la mise en lignes et conserver tous les accents français sans supprimer aucun mot.")
        for lines in [1,2] {
            let result=SubtitleFormat.reflow([long],lines:lines,maxChars:25,maxDuration:6)
            try SubtitleFormat.validate(result)
            try check(result.first?.start==long.start && result.last?.end==long.end,"Reflow preserves interval")
            try check(result.allSatisfy{$0.text.components(separatedBy:"\n").count<=lines},"Line count limit")
            let normalize:(String)->String = {$0.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")}
            try check(normalize(result.map(\.text).joined(separator:" "))==normalize(long.text),"Reflow preserves every word")
        }
        // Regression: duration-driven chunks must still wrap and preserve edited words.
        var edited=SubtitleCue(start:3,end:63,text:"Bonjour à François : voici une anticonstitutionnellement longue explication avec de tout petits mots et des accents préservés après correction manuelle.")
        edited.words=[SubtitleWord(text:"FAUTE INITIALE",start:3,end:4)]
        let normalize:(String)->String = {$0.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")}
        for lines in [1,2] {
            for chars in [18,42] {
                for duration in [1.1,2.5,6.0] {
                    let result=SubtitleFormat.reflow([edited],lines:lines,maxChars:chars,maxDuration:duration)
                    try SubtitleFormat.validate(result)
                    try check(normalize(result.map(\.text).joined(separator:" "))==normalize(edited.text),"Duration reflow preserves corrected text")
                    try check(result.first?.start==edited.start && result.last?.end==edited.end,"Duration reflow preserves endpoints")
                    for cue in result {
                        let rows=cue.text.components(separatedBy:"\n")
                        try check(rows.count<=lines,"Duration reflow respects line count")
                        try check(rows.allSatisfy{$0.count<=chars || $0.split(separator:" ").count==1},"Only an indivisible word may exceed character limit")
                        try check(cue.end-cue.start<=duration+0.000_001 || cue.text.split(whereSeparator:{$0.isWhitespace}).count==1,"Only an indivisible timed word may exceed duration")
                    }
                    let restored=try SubtitleFormat.importSRT(SubtitleFormat.srt(result))
                    try check(normalize(restored.map(\.text).joined(separator:" "))==normalize(edited.text),"Edited text survives reflow SRT roundtrip")
                }
            }
        }
        try check(p.exportSegments[0].start==12.625,"Export offset applies to start")
        try check(p.exportSegments[0].end==16.25,"Export offset applies to end")
        let offsetSRT=try SubtitleFormat.srt(p.exportSegments)
        try check(offsetSRT.contains("00:00:12,625 --> 00:00:16,250"),"Export offset SRT timestamps")
        #if FILMCRAFT_INTEGRATION
        let adapter=SubtitleFilmCraftAdapter.style(SubtitleStyle())
        try check(abs(adapter.margin-70.0/1080)<0.000_001,"FilmCraft margin pixels normalized")
        try check(adapter.size==70,"FilmCraft font size remains in pixels")
        let defaultProps=SubtitleFilmCraftAdapter.graphicProperties(defaults.style,canvas:.fullHD)
        try check(defaultProps["stroke_type"] as? String == "Outer" && defaultProps["stroke"] as? Bool == false,"FilmCraft default outline disabled and outside")
        var outlined=defaults.style;outlined.outline=4
        let props=SubtitleFilmCraftAdapter.graphicProperties(outlined,canvas:SubtitleCanvas(width:3840,height:2160))
        try check(props["stroke_type"] as? String == "Outer" && props["stroke_width"] as? Double == 8 && props["stroke"] as? Bool == true,"FilmCraft outer outline scales with frame height")
        #endif
        print("Document checks passed: timing, overlaps, UTF-8, SRT/VTT/ASS, styles, projects, 12 mixed-word reflow regressions, FilmCraft style adapter and export offset.")

    }
}
