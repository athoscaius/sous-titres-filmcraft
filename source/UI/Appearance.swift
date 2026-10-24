import AppKit
import AVKit

enum Palette {
    static let chrome = NSColor(white: 50/255, alpha: 1)
    static let canvas = NSColor(white: 40/255, alpha: 1)
    static let field = NSColor(white: 36/255, alpha: 1)
    static let border = NSColor(white: 74/255, alpha: 1)
    static let text = NSColor(white: 222/255, alpha: 1)
    static let dim = NSColor(white: 178/255, alpha: 1)
    static let accent = NSColor(srgbRed: 55/255, green: 142/255, blue: 240/255, alpha: 1)
}
final class PanelButton: NSButton {
    var primary = false
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        let fill = primary ? Palette.accent : Palette.field
        (isHighlighted ? fill.blended(withFraction: 0.18, of: .white)! : fill).withAlphaComponent(isEnabled ? 1 : 0.35).setFill(); path.fill()
        Palette.border.setStroke(); path.stroke()
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key:Any] = [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: (primary ? NSColor.white : Palette.text).withAlphaComponent(isEnabled ? 1 : 0.35), .paragraphStyle:p]
        let h = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 8, y: (bounds.height-h)/2, width: bounds.width-16, height: h+2), withAttributes: attrs)
    }
}
final class TopAlignedClipView:NSClipView {override var isFlipped:Bool {true}}
final class CanvasPreview:NSView {
    let canvasView=NSView()
    var canvas=SubtitleCanvas.fullHD {didSet{needsLayout=true}}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Palette.field.cgColor;canvasView.wantsLayer=true;canvasView.layer?.backgroundColor=NSColor.black.cgColor;addSubview(canvasView)}
    required init?(coder:NSCoder){fatalError("init(coder:)")}
    override func layout(){super.layout();canvasView.frame=canvas.fitted(in:bounds)}
}
final class SubtitleOverlay: NSView {
    var text = "" { didSet { if oldValue != text {needsDisplay = true} } }
    var style = SubtitleStyle() { didSet { if oldValue != style {needsDisplay = true} } }
    var canvas=SubtitleCanvas.fullHD {didSet{if oldValue != canvas{needsDisplay=true}}}
    var lineLimit=1 {didSet{if oldValue != lineLimit{needsDisplay=true}}}
    private var cache:(text:String,style:SubtitleStyle,canvas:SubtitleCanvas,lines:Int,result:SubtitleTextLayout)?
    func textLayout()->SubtitleTextLayout {
        if let cache,cache.text==text,cache.style==style,cache.canvas==canvas,cache.lines==lineLimit{return cache.result}
        let result=SubtitleTextLayout.make(text:text,style:style,canvas:canvas,lines:lineLimit)
        cache=(text,style,canvas,lineLimit,result);return result
    }
    var videoSize:NSSize {
        get{NSSize(width:canvas.width,height:canvas.height)}
        set{canvas=SubtitleCanvas(width:newValue.width,height:newValue.height)}
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty,bounds.width>0,bounds.height>0,canvas.isValid,let context=NSGraphicsContext.current?.cgContext else{return}
        let area=canvas.fitted(in:bounds)
        let layout=textLayout()
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let attributes:[NSAttributedString.Key:Any]=[.font:layout.font,.foregroundColor:NSColor(hex:style.color),.paragraphStyle:paragraph]
        let rect=NSRect(x:layout.frame.minX,y:canvas.height-layout.frame.maxY,width:layout.frame.width,height:layout.frame.height)
        let options:NSString.DrawingOptions=[.usesLineFragmentOrigin,.usesFontLeading]
        context.saveGState();defer{context.restoreGState()}
        context.translateBy(x:area.minX,y:area.minY);context.scaleBy(x:area.width/canvas.width,y:area.height/canvas.height)
        if layout.outline>0 {
            var outlineAttributes=attributes
            outlineAttributes[.strokeColor]=NSColor(hex:style.outlineColor)
            outlineAttributes[.strokeWidth]=2*layout.outline/max(layout.fontSize,0.01)*100
            NSAttributedString(string:layout.text,attributes:outlineAttributes).draw(with:rect,options:options)
        }
        NSAttributedString(string:layout.text,attributes:attributes).draw(with:rect,options:options)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let n = UInt32(hex.dropFirst(), radix:16) ?? 0xFFFFFF
        self.init(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
    }
    var rgbHex: String {
        let c = usingColorSpace(.sRGB) ?? .white
        return String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
    }
}
