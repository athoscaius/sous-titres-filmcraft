import Foundation

enum SubtitleSelfTest {
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool,_ name:String) throws {if !value(){throw SubtitleError.invalid(name)}}
        func rejects(_ name:String,_ body:() throws->Void) throws {var failed=false;do{try body()}catch{failed=true};try check(failed,name)}
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
        var style=SubtitleStyle();style.color="#123456";style.top=true;style.fontSize=64
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
        try check(adapter.size==52,"FilmCraft font size remains in pixels")
        #endif
        print("Document checks passed: timing, overlaps, UTF-8, SRT/VTT/ASS, styles, projects, 12 mixed-word reflow regressions, FilmCraft style adapter and export offset.")

    }
}
