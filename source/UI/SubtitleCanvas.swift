import AppKit

struct SubtitleCanvas:Codable,Equatable {
    var width:Double
    var height:Double
    var pixelAspect:Double=1
    static let fullHD=SubtitleCanvas(width:1920,height:1080)
    var isValid:Bool {width.isFinite && height.isFinite && pixelAspect.isFinite && (1...65536).contains(width) && (1...65536).contains(height) && (0.05...20).contains(pixelAspect)}
    var ratio:Double {width*pixelAspect/height}
    // Preserve readable type across orientations; double its pixels for a 4K frame.
    var scale:Double {min(width,height)/1080}
    var label:String {
        func gcd(_ a:Int,_ b:Int)->Int {b==0 ? a:gcd(b,a%b)}
        let a=Int((width*pixelAspect).rounded()),b=Int(height.rounded()),divisor=max(1,gcd(a,b))
        let aspect=(a/divisor<=100 && b/divisor<=100) ? "\(a/divisor):\(b/divisor)":String(format:"%.2f:1",ratio)
        return "\(Int(width)) × \(Int(height)) · \(aspect)"
    }
    func fitted(in bounds:NSRect)->NSRect {
        var area=bounds
        if bounds.width/bounds.height>ratio {area.size.width=bounds.height*ratio;area.origin.x += (bounds.width-area.width)/2}
        else {area.size.height=bounds.width/ratio;area.origin.y += (bounds.height-area.height)/2}
        return area
    }
    static func from(settings:[String:Any]) throws -> Self {
        guard let w=(settings["width"] as? NSNumber)?.doubleValue,let h=(settings["height"] as? NSNumber)?.doubleValue else{throw SubtitleError.invalid("Résolution de la séquence indisponible.")}
        let par=settings["par"] as? [NSNumber]
        let value=SubtitleCanvas(width:w,height:h,pixelAspect:par.flatMap{$0.count==2 && $0[1].doubleValue>0 ? $0[0].doubleValue/$0[1].doubleValue:nil} ?? 1)
        guard value.isValid else {throw SubtitleError.invalid("Le format de la séquence est invalide.")};return value
    }
}
struct SubtitleTextLayout {
    let text:String
    let font:NSFont
    let frame:NSRect // Frame coordinates, origin at the top left, matching FilmCraft.
    let outline:Double
    var fontSize:Double {font.pointSize}
    var baseline:Double {frame.minY+font.ascender}
    static func make(text:String,style:SubtitleStyle,canvas:SubtitleCanvas,lines:Int)->Self {
        let outline=style.outline*canvas.scale
        let marginX=canvas.width*0.05
        let marginY=canvas.height*0.05
        let available=max(1,canvas.width-2*marginX-2*outline-4*canvas.scale)
        let maximumHeight=max(1,canvas.height*0.3)
        let paragraphs=text.components(separatedBy:"\n")
        let lineLimit=max(lines,paragraphs.count)
        func font(_ size:Double)->NSFont {
            let base=NSFont(name:style.fontName,size:size) ?? .systemFont(ofSize:size)
            return style.bold ? NSFontManager.shared.convert(base,toHaveTrait:.boldFontMask):base
        }
        func measure(_ candidate:String,_ font:NSFont)->Double {(candidate as NSString).size(withAttributes:[.font:font]).width}
        func wrapped(_ font:NSFont)->[String] {
            if lineLimit==1{return [text]}
            return paragraphs.flatMap {paragraph->[String] in
                var rows:[String]=[],row=""
                for word in paragraph.split(whereSeparator:{$0.isWhitespace}) {
                    let candidate=row.isEmpty ? String(word):row+" "+word
                    if !row.isEmpty && measure(candidate,font)>available {rows.append(row);row=String(word)}else{row=candidate}
                }
                rows.append(row);return rows
            }
        }
        let base=max(0.1,style.fontSize*canvas.scale)
        var low=max(0.01,base/1000),high=base
        func fits(_ size:Double)->Bool {
            let f=font(size),rows=wrapped(f)
            return rows.count<=lineLimit && rows.allSatisfy{measure($0,f)<=available} && Double(rows.count)*(f.ascender-f.descender+f.leading)+4*canvas.scale<=maximumHeight
        }
        if !fits(base){for _ in 0..<28 {let middle=(low+high)/2;if fits(middle){low=middle}else{high=middle}}}else{low=base}
        let f=font(low),rows=wrapped(f),width=min(available,(rows.map{measure($0,f)}.max() ?? 0)+4*canvas.scale)
        let rendered=rows.joined(separator:"\n")
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let measured=(rendered as NSString).boundingRect(with:NSSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:f,.paragraphStyle:paragraph])
        let height=max(1,ceil(measured.height)+4*canvas.scale)
        let x=marginX+max(0,canvas.width-2*marginX-width)*style.positionX
        let y=marginY+max(0,canvas.height-2*marginY-height)*style.positionY
        return Self(text:rendered,font:f,frame:NSRect(x:x,y:y,width:width,height:height),outline:outline)
    }
}
extension SubtitleProject {
    var outputCanvas:SubtitleCanvas {canvas ?? .fullHD}
    var adaptiveMaxChars:Int {
        let format=outputCanvas,size=style.fontSize*format.scale
        let font=NSFont(name:style.fontName,size:size) ?? .systemFont(ofSize:size)
        let sample="Une voix française raconte une histoire."
        let average=(sample as NSString).size(withAttributes:[.font:font]).width/Double(sample.count)
        return min(maxChars,max(8,Int((format.width*0.9-2*style.outline*format.scale)/max(average,1))))
    }
}
