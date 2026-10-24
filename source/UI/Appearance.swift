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
final class SubtitleOverlay: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var style = SubtitleStyle() { didSet { needsDisplay = true } }
    var videoSize = NSSize(width: 1920, height: 1080) { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty, bounds.width > 0, videoSize.width > 0, videoSize.height > 0 else { return }
        let videoRatio = videoSize.width/videoSize.height
        var area = bounds
        if bounds.width/bounds.height > videoRatio { area.size.width = bounds.height*videoRatio; area.origin.x = (bounds.width-area.width)/2 }
        else { area.size.height = bounds.width/videoRatio; area.origin.y = (bounds.height-area.height)/2 }
        let scale = area.height/1080
        var font = NSFont(name: style.fontName, size: style.fontSize*scale) ?? .systemFont(ofSize: style.fontSize*scale)
        if style.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byWordWrapping
        let color = NSColor(hex: style.color)
        let attributes: [NSAttributedString.Key:Any] = [.font:font, .foregroundColor:color, .paragraphStyle:p]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let maximum=max(1,area.width*0.9)
        let measured=attributed.boundingRect(with:NSSize(width:maximum,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading])
        let width=min(maximum,ceil(measured.width)+4),height=ceil(measured.height)+4
        let x=area.minX+(area.width-width)*style.positionX
        let y=area.minY+(area.height-height)*(1-style.positionY)
        let rect=NSRect(x:x,y:y,width:width,height:height)
        let options:NSString.DrawingOptions=[.usesLineFragmentOrigin,.usesFontLeading]
        if style.outline > 0 {
            // AppKit strokes straddle the glyph edge. Draw twice the requested
            // width first, then restore the full glyph fill above the inner half.
            var outlineAttributes=attributes
            outlineAttributes[.strokeColor]=NSColor(hex:style.outlineColor)
            outlineAttributes[.strokeWidth]=2*style.outline/max(style.fontSize,1)*100
            NSAttributedString(string:text,attributes:outlineAttributes).draw(with:rect,options:options)
        }
        attributed.draw(with:rect,options:options)
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
