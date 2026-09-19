import Foundation

/// What the Mac will let Forge see through the camera.
enum CameraAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied
}
