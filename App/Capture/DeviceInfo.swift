import UIKit
import RoomPlan
import FloorPlanCore

enum DeviceInfo {
    /// Identificador de hardware (ex.: `iPhone16,2`).
    static var hardwareModel: String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    @MainActor
    static func metadata() -> DeviceMetadata {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return DeviceMetadata(deviceModel: hardwareModel,
                              systemName: UIDevice.current.systemName,
                              systemVersion: UIDevice.current.systemVersion,
                              appVersion: "\(version) (\(build))",
                              lidarSupported: RoomCaptureSession.isSupported)
    }
}
