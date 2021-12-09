import Foundation


class Libre3: Libre2 {


    enum UUID: String, CustomStringConvertible, CaseIterable {

        /// Advertised primary data service
        case data = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Requests data by writing 13 bytes ending in 0100 for recent data (195A), 0200 for past data (1AB8)
        /// Notifies 10 bytes at the end of stream ending in 0100 for 195A, 0200 for 1AB8
        case data_1338 = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // Receiving "Encryption is insufficient" error when activating notifications
        case data_1482 = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Read"]

        /// Notifies every minute 35 bytes as two packets of 15 + 20 bytes ending in a sequential id
        case oneMinuteReading = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a first stream of recent data while the curve is drawn on display
        case data_195A = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a second longer stream of past data
        case data_1AB8 = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies 20 + 20 bytes towards the end of activation (session info)
        case data_1BEE = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies the final stream of data during activation
        case data_1D24 = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Secondary service
        case secondary = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"

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
        case secondary_2198 = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Notifies the 23-byte security challenge + prefixes
        /// Writes the 40-byte unlock payload + prefixes
        /// Notifies the 67-byte session info + prefixes
        case secondary_22CE = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Writes and notifies 20-byte packets during activation
        case secondary_23FA = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        var description: String {
            switch self {
            case .data:             return "data service"
            case .data_1338:        return "data 0x1338"
            case .data_1482:        return "data 0x1482"
            case .oneMinuteReading: return "one-minute reading"
            case .data_195A:        return "data 0x195A"
            case .data_1AB8:        return "data 0x1AB8"
            case .data_1BEE:        return "data 0x1BEE"
            case .data_1D24:        return "data 0x1D24"
            case .secondary:        return "secondary service"
            case .secondary_2198:   return "secondary 0x2198"
            case .secondary_22CE:   return "secondary 0x22CE"
            case .secondary_23FA:   return "secondary 0x23FA"
            }
        }
    }

    class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }


    // maximum packet size is 20
    // notified packets are prefixed by 00, 01, 02, ...
    // written packets are prefixed by 00 00, 12 00, 24 00, 36 00, ...
    // data packets are terminated by a sequential Int
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
    // notify 177A  15 + 20 bytes       // one-minute reading
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
    // write  23FA  20 * 9 bytes
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
    // write  1338  13 bytes
    // notify 1BBE  20 + 20 bytes
    // notify 1338  10 bytes
    // write  1338  13 bytes
    // notify 1D24  20 * 10 + 15 bytes
    // notify 1338  10 bytes


    /// Single byte command written to 0x2198
    enum Command: UInt8, CustomStringConvertible {

        // can be sent sequentially not only during the initial sensor activation
        case activate_01    = 0x01
        case activate_02    = 0x02
        case activate_03    = 0x03
        case activate_09    = 0x09
        case activate_0D    = 0x0D
        case activate_0E    = 0x0E

        /// final command to get a 67-byte session info
        case getSessionInfo = 0x08

        /// first command sent when reconnecting
        case readChallenge  = 0x11

        var description: String {
            switch self {
            case .activate_01:    return "activation 1st command"
            case .activate_02:    return "activation 2nd command"
            case .activate_03:    return "activation 3rd command"
            case .activate_09:    return "activation 0x09 command"
            case .activate_0D:    return "activation 0x0D command"
            case .activate_0E:    return "activation 0x0E command"
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
            // TODO: are states 03 and 07 skipped?
            // state 04 detected already after 20 minutes, 08 for a detached sensor
            // 05 lasts more than 12 hours, almost 24, before that BLE shuts down
            let sensorState = patchInfo[16]
            state = SensorState(rawValue: sensorState <= 2 ? sensorState: sensorState - 1) ?? .unknown
            log("Libre 3: state: \(state.description.lowercased()) (0x\(sensorState.hex))")
            let serialNumber = Data(patchInfo[17...25])
            serial = serialNumber.string
            log("Libre 3: serial number: \(serialNumber.string) (0x\(serialNumber.hex))")

        }
    }


    func send(command cmd: Command) {
        log("Bluetooth: sending to \(type) \(transmitter!.peripheral!.name!) `\(cmd.description)` command 0x\(cmd.rawValue.hex)")
        currentCommand = cmd
        transmitter!.write(Data([cmd.rawValue]), for: UUID.secondary_2198.rawValue, .withResponse)
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
            str += data[offset + 1 ..< offsetEnd].hexBytes
            payload += data[offset + 1 ..< offsetEnd]
            _ = data.formIndex(&offset, offsetBy: 20, limitedBy: endIndex)
            if offset < endIndex { str += "\n" }
        }
        return (payload, str)
    }


    // TODO
    func write(_ data: Data, for uuid: String = "") {
        let packets = (data.count - 1) / 18 + 1
        for i in 0 ... packets - 1 {
            let offset = i * 18
            let id = Data([UInt8(offset & 0xFF), UInt8(offset >> 8)])
            let packet = id + data[offset ... min(offset + 17, data.count - 1)]
            debugLog("TEST: packet to write: \(packet.hexBytes)")
        }
    }


    /// called by Abbott Trasmitter class
    func read(_ data: Data, for uuid: String) {

        switch UUID(rawValue: uuid) {

        case .data_1338:
            if data.count == 10 {
                let suffix = data.suffix(2).hex
                if suffix == "0100" {
                    // TODO: end of 1950 recent data
                } else if suffix == "0200" {
                    // TODO: end of 1AB8 past data
                }
                buffer = Data()
            }

            // The Libre 3 sends every minute 35 bytes as two packets of 15 + 20 bytes
            // The final Int is a sequential id
        case .oneMinuteReading:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
                if buffer.count == 35 {
                    let payload = buffer.prefix(33)
                    let id = UInt16(buffer.suffix(2))
                    log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
                    buffer = Data()
                }
            }

        case .data_195A, .data_1AB8:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let payload = data.prefix(18)
            let id = UInt16(data.suffix(2))
            log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
            // TODO: the end of the stream is notified by 1338 with 10 bytes ending in 0100 for 195A, 0200 for 1AB8

        case .secondary_2198:
            if data.count == 2 {
                expectedStreamSize = Int(data[1] + data[1] / 20 + 1)
                log("\(type) \(transmitter!.peripheral!.name!): expected response size: \(expectedStreamSize) bytes")
            }

        case .secondary_22CE:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data

                if buffer.count == expectedStreamSize {

                    let (payload, hexDump) = parsePackets(buffer)
                    log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count) bytes):\n\(hexDump)")

                    switch currentCommand {

                    case .readChallenge:

                        // getting: df4bd2f783178e3ab918183e5fed2b2b c201 0000 e703a7
                        //                                        increasing

                        let challengeCount = UInt16(payload[16...17])
                        log("\(type) \(transmitter!.peripheral!.name!): security challenge # \(challengeCount.hex): \(payload.hex)")

                        if main.settings.debugLevel > 0 {
                            let bytes = "03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15".bytes
                            write(bytes)
                        }

                        // TODO: write the unlock payload
                        log("\(type) \(transmitter!.peripheral!.name!): TEST: sending to 0x22CE zeroed packets of 20 + 20 + 6 bytes prefixed by 00 00, 12 00, 24 00 (it should be the unlock payload)")
                        transmitter!.write("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00".bytes, for: uuid, .withResponse)
                        transmitter!.write("12 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00".bytes, for: uuid, .withResponse)
                        transmitter!.write("24 00 00 00 00 00".bytes, for: uuid, .withResponse)

                        // writing .getSessionInfo makes the Libre 3 disconnect
                        send(command: .getSessionInfo)

                    case .getSessionInfo:
                        log("\(type) \(transmitter!.peripheral!.name!): session info: \(payload.hex)")

                    default:
                        break // currentCommand
                    }

                    buffer = Data()
                    expectedStreamSize = 0
                    currentCommand = nil

                }
            }

        default:
            break  // uuid
        }

    }

}


// MARK: - PacketLogger logs

// Written to 23FA after the commands 01 and 02 both during activation and reconnection:

// 00 00 03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10
// 12 00 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36
// 24 00 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D
// 36 00 DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94
// 48 00 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB
// 5A 00 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98
// 6C 00 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9
// 7E 00 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF
// 90 00 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15

// 03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15
