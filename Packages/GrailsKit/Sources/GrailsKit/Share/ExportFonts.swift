import Foundation

/// The app's typefaces, handed over at launch so exports can carry them (an HTML file embeds them; a PDF draws with them).
/// Left empty (the command-line tools), exports use the system fonts.
public enum ExportFonts {
    nonisolated(unsafe) public static var display: Data?
    nonisolated(unsafe) public static var body: Data?
    nonisolated(unsafe) public static var bodyBold: Data?
}
