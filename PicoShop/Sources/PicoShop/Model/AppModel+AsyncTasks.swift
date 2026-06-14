import SwiftUI

extension AppModel {
    func beginRasterTaskVersion() -> UInt64 {
        rasterizeVersion &+= 1
        return rasterizeVersion
    }

    func isCurrentRasterTask(_ version: UInt64) -> Bool {
        rasterizeVersion == version
    }

    func cancelRasterTasks() {
        rasterizeVersion &+= 1
        isMoveExtracting = false
    }
}
