import AppKit

enum AnimationFrames {
    // Use symbols that are guaranteed to exist and visually represent growth
    static let frames = [
        "leaf",
        "leaf.fill",
        "tree",
        "tree.fill",
    ]

    static let idleSymbol = "leaf.fill"

    static func image(for index: Int) -> NSImage? {
        let name = frames[index % frames.count]
        return makeImage(symbolName: name)
    }

    static func idleImage() -> NSImage? {
        makeImage(symbolName: idleSymbol)
    }

    private static func makeImage(symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Token Garden")
        return image?.withSymbolConfiguration(config)
    }
}
