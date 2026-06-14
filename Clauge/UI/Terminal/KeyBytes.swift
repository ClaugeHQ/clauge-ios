import Foundation

/// Exact escape sequences sent by the terminal key bar. Verbatim from the
/// Android KeyBytes so both clients drive the PTY identically.
enum KeyBytes {
    static let esc: [UInt8] = [0x1b]
    static let tab: [UInt8] = [0x09]
    static let ctrlC: [UInt8] = [0x03]
    static let up: [UInt8] = [0x1b, 0x5b, 0x41]    // ESC [ A
    static let down: [UInt8] = [0x1b, 0x5b, 0x42]  // ESC [ B
    static let right: [UInt8] = [0x1b, 0x5b, 0x43] // ESC [ C
    static let left: [UInt8] = [0x1b, 0x5b, 0x44]  // ESC [ D

    static func base64(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
    }
}
