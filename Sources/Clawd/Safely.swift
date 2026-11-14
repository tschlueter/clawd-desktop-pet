import Foundation
import ObjCExceptions

/// Objective-C-Exceptions (AVFoundation, Core Animation …) kann Swift nicht fangen. AppKit fängt sie
/// zwar stumm im Run Loop ab – ein Timer, in dessen Aufruf das passiert, feuert danach aber nie wieder.
/// So ist Clawd einmal eingefroren (Audiogerät weg beim Zuklappen, mitten im Videocall).
enum Safely {
    /// `block` ausführen; eine Exception wird protokolliert statt weiterzufliegen.
    /// - Returns: false, wenn eine Exception abgefangen wurde.
    @discardableResult
    static func run(_ label: String, _ block: () -> Void) -> Bool {
        guard let e = ObjCTry(block) else { return true }
        DebugLog.write("\(label): Exception abgefangen – \(e.name.rawValue): \(e.reason ?? "?")")
        return false
    }
}
