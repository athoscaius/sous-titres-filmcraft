import AppKit
@main struct Test { static func main() throws {
    let before = try FilmCraftBridge.shared.snapshot()
    guard before.projectPath == nil, before.sequenceName == "Test compagnon — sous-titres" else { fatalError("Not the isolated fixture") }
    var style = FilmCraftCaptionStyle()
    style.font = "Helvetica Neue"
    style.size = 62
    style.outline = 3
    style.background = true
    style.backgroundColor = "#112233aa"
    style.anchor = "top"
    let result = try FilmCraftBridge.shared.importCaptions(srtURL: URL(fileURLWithPath:"/private/tmp/artcraft-filmcraft-bridge-test/captions.srt"), style: style, expected: before)
    precondition(result.captions == 2)
    print(result.message)
    do { _ = try FilmCraftBridge.shared.importCaptions(srtURL: URL(fileURLWithPath:"/private/tmp/artcraft-filmcraft-bridge-test/captions.srt"), style:style, expected: before); fatalError("Stale snapshot accepted") }
    catch { print("Stale snapshot rejected:", error.localizedDescription) }
} }
