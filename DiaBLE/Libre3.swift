import Foundation


class Libre3: Sensor {

    // TODO: https://github.com/gui-dos/DiaBLE/discussions/7

    func parsePatchInfo() {
        if patchInfo.count == 28 {
            log("Libre 3: patch info CRC: \(patchInfo.suffix(2).hex), computed CRC: \(patchInfo.prefix(26).crc16.hex)")
            log("Libre 3: status: \(patchInfo[16])")
        }
    }
}
