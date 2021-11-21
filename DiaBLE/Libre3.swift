import Foundation


class Libre3: Libre2 {


    enum UUID: String, CustomStringConvertible, CaseIterable {

        /// Advertised primary data service
        case data =      "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Requests past data by writing 13 zero-terminated bytes, notifies 10 zero-terminated bytes at the end of stream
        case data_1338 = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // Receiving "Encryption is insufficient" error when activating notifications
        case data_1482 = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Read"]

        /// Notifies every minute 35 bytes as two packets of 15 + 20 zero-terminated bytes
        case data_177A = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a first stream of recent data while the curve is drawn on display
        case data_195A = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a second longer stream of past data
        case data_1AB8 = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies 20 + 20 bytes towards the end of activation (session info?)
        case data_1BEE = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies the final stream of data during activation
        case data_1D24 = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Secondary service
        case unknown1 =  "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Writes a single byte command, may notify in the second byte the effective length of the returned stripped stream
        /// 01: very first command when activating a sensor
        /// 02: written immediately after 01
        /// 03: third command sent during activation
        /// 04: notified immediately after 03
        /// 08: read the final 67-byte session info, notifies 08 43 -> 22CE notifies 67 bytes + prefixes
        /// 09: during activation notifies A0 8C -> 23FA notifies 140 bytes + prefixes
        /// 0D: during activation is written before 0E
        /// 0E: during activation notifies 0F 41 -> 23FA notifies 69 bytes
        /// 11: read the 23-byte security challenge, notifies 08 17
        case _2198 = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Notifies the 23-byte security challenge + prefixes
        /// Writes the 40-byte unlock payload + prefixes
        /// Notifies the 67-byte session info + prefixes
        case _22CE = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Writes and notifies 20-byte packets during activation
        case _23FA = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        var description: String {
            switch self {
            case .data:      return "Libre 3 data service"
            case .data_1338: return "Libre 3 data 0x1338"
            case .data_1482: return "Libre 3 data 0x1482"
            case .data_177A: return "Libre 3 data 0x177A"
            case .data_195A: return "Libre 3 data 0x195A"
            case .data_1AB8: return "Libre 3 data 0x1AB8"
            case .data_1BEE: return "Libre 3 data 0x1BEE"
            case .data_1D24: return "Libre 3 data 0x1D24"
            case .unknown1:  return "Libre 3 unknown service"
            case ._2198:     return "Libre 3 unknown 0x2198"
            case ._22CE:     return "Libre 3 unknown 0x22CE"
            case ._23FA:     return "Libre 3 unknown 0x23FA"
            }
        }
    }


    // maximum packet size is 20
    // notified packets are prefixed by 00, 01, 02, ...
    // written packets are prefixed by 00 00, 12 00, 24 00, 36 00, ...
    //
    // Connection:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 + 20 + 6 bytes   // 40-byte unlock payload
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte session info
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes
    // enable notifications for 177A
    // write  1338  13 bytes
    // notify 177A  15 + 20 bytes
    // notify 195A  20-byte packets of recent data
    // notify 1338  10 bytes
    // write  1338  13 bytes
    // notify 1AB8  20-byte packets of past data
    // notify 1338  10 byte
    //
    // Activation:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  01
    // write  2198  02
    // write  23FA  20 * 9 bytes (first packet: 0000 0300 0102 0304 0506 0708 090A 0B0C 0D0E 0F10)
    // write  2198  03
    // notify 2198  04
    // write  2198  09
    // notify 2198  A0 8C
    // notify 23FA  20 * 7 + 8 bytes
    // write  2198  0D
    // write  23FA  20 * 3 + 13 bytes
    // write  2198  0E
    // notify 2198  0F 41
    // notify 23FA  20 * 3 + 9 bytes
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 * 2 + 6 bytes    // 40-byte unlock payload
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte session info
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes
    // enable notifications for 177A
    // write  1338  13 bytes (final 0)
    // notify 1BBE  20 + 20 bytes
    // notify 1338  10 bytes (final 0)
    // write  1338  13 bytes
    // notify 1D24  20 * 10 + 15 bytes
    // notify 1338  10 bytes (final 0)


    /// Single byte command written to 0x2198
    enum Command: UInt8, CustomStringConvertible {

        /// final command to get a 67-byte session info
        case getSessionInfo  = 0x08

        /// first command sent when reconnecting
        case readChallenge   = 0x11

        var description: String {
            switch self {
            case .getSessionInfo: return "get session info"
            case .readChallenge:  return "read security challenge"
            }
        }
    }


    var buffer: Data = Data()
    var currentCommand: Command?
    var expectedStreamSize = 0


    // TODO: https://github.com/gui-dos/DiaBLE/discussions/7 - "Libre 3 NFC"

    func parsePatchInfo() {
        if patchInfo.count == 28 {
            log("Libre 3: patch info: \(patchInfo.hexBytes), CRC: \(Data(patchInfo.suffix(2).reversed()).hex), computed CRC: \(patchInfo[2...25].crc16.hex)")
            log("Libre 3: state: \(patchInfo[16])")
        }
    }


    func parsePackets(_ data: Data) -> (Data, String) {
        var payload = Data()
        var str = ""
        var offset = data.startIndex
        var offsetEnd = offset
        let endIndex = data.endIndex
        while offset < endIndex {
            str += data[offset].hex + "  "
            _ = data.formIndex(&offsetEnd, offsetBy: 20, limitedBy: endIndex)
            print("offset: \(offset), offsetEnd: \(offsetEnd)")
            str += data[offset + 1 ..< offsetEnd].hexBytes
            payload += data[offset + 1 ..< offsetEnd]
            _ = data.formIndex(&offset, offsetBy: 20, limitedBy: endIndex)
            if offset < endIndex { str += "\n" }
        }
        return (payload, str)
    }


    /// called by Abbott Trasmitter class
    func read(_ data: Data, for uuid: String, from device: Transmitter) {

        switch UUID(rawValue: uuid) {

        case ._2198:
            if data.count == 2 {
                expectedStreamSize = Int(data[1] + data[1] / 20 + 1)
                log("\(type) \(device.peripheral!.name!): will receive \(expectedStreamSize) bytes")
            }

        case ._22CE:
            if buffer.count == 0 {
                buffer = Data(data)

            } else if buffer.count == 20 {
                buffer += data
                if buffer.count == 25 {

                    // TODO: split the 20-byte packets and the leading progressive prefixes

                    let(payload, hexDump) = parsePackets(buffer)
                    log("\(type) \(device.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count)):\n\(hexDump)")
                    buffer = Data()

                    log("\(type) \(device.peripheral!.name!): TEST: sending 0x22CE packets of 20 + 20 + 6 bytes prefixed by 00 00, 12 00, 24 00")
                    device.write("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00".bytes, for: uuid, .withResponse)
                    device.write("12 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00".bytes, for: uuid, .withResponse)
                    device.write("24 00 00 00 00 00".bytes, for: uuid, .withResponse)


                    // writing .getSessionInfo makes the Libre 3 disconnect
                    let cmd = Libre3.Command.getSessionInfo
                    log("Bluetooth: sending Libre 3 `\(cmd.description)` command 0x\(cmd.rawValue.hex)")
                    device.write(Data([cmd.rawValue]), for: Libre3.UUID._2198.rawValue, .withResponse)
                }
            }


        default:
            break
        }

    }

}
