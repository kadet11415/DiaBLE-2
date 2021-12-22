import Foundation


class Libre3: Sensor {


    enum State: UInt8, CustomStringConvertible {
        case manufacturing      = 0x00    // PATCH_STATE_MANUFACTURING
        case storage            = 0x01    // PATCH_STATE_STORAGE
        case insertionDetection = 0x02    // PATCH_STATE_INSERTION_DETECTION
        case insertionFailed    = 0x03    // PATCH_STATE_INSERTION_FAILED
        case paired             = 0x04    // PATCH_STATE_PAIRED
        case expired            = 0x05    // PATCH_STATE_EXPIRED
        case terminated         = 0x06    // PATCH_STATE_TERMINATED_NORMAL
        case error              = 0x07    // PATCH_STATE_ERROR
        case errorTerminated    = 0x08    // PATCH_STATE_ERROR_TERMINATED

        var description: String {
            switch self {
            case .manufacturing:      return "Manufacturing"
            case .storage:            return "Not activated"
            case .insertionDetection: return "Insertion detection"
            case .insertionFailed:    return "Insertion failed"
            case .paired:             return "Paired"
            case .expired:            return "Expired"
            case .terminated:         return "Terminated"
            case .error:              return "Error"
            case .errorTerminated:    return "Terminated (error)"
            }
        }
    }


    // TODO
    struct PatchInfo {
        let NFC_Key: Int
        let localization: Int
        let generation: Int
        let puckGeneration: Int
        let wearDuration: Int
        let warmupTime: Int
        let productType: Int
        let state: State
        let fwVersion: Data
        let compressedSN: Data
        let securityVersion: Int
    }


    enum UUID: String, CustomStringConvertible, CaseIterable {

        /// Advertised primary data service
        case data = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Requests data by writing 13 bytes embedding a "patch control command" (7 bytes?)
        /// and a final sequential Int (starting by 01 00) since it is enqueued
        /// Notifies at the end of the data stream 10 bytes ending in the enqueued id
        /// (for example 01 00 and 02 00 when receiving recent and past data on 195A and 1AB8)
        case patchControl = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // Receiving "Encryption is insufficient" error when activating notifications
        /// Notifies 18 bytes ending in 01 00 during a connection
        case patchStatus = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Read"]

        /// Notifies every minute 35 bytes as two packets of 15 + 20 bytes ending in a sequential id
        case oneMinuteReading = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a first stream of recent data while the curve is drawn on display
        case historicalData = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a second longer stream of past data
        case clinicalData = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies 20 + 20 bytes towards the end of activation
        /// Notifies 20 bytes when shutting down a sensor (CTRL_CMD_SHUTDOWN_PATCH)
        /// and at the first connection after activation
        case eventLog = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies the final stream of data during activation
        case factoryData = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Security service
        case security = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"

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
        case securityCommands = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Notifies the 23-byte security challenge + prefixes
        /// Writes the 40-byte unlock payload + prefixes
        /// Notifies the 67-byte session info + prefixes
        case challengeData = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Writes and notifies 20-byte packets during activation and repairing a sensor
        case certificateData = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // TODO:
        case debug = "08982400-EF89-11E9-81B4-2A2AE2DBCCE44"
        case bleLogin = "F001"

        var description: String {
            switch self {
            case .data:             return "data service"
            case .patchControl:     return "patch control"
            case .patchStatus:      return "patch status"
            case .oneMinuteReading: return "one-minute reading"
            case .historicalData:   return "historical data"
            case .clinicalData:     return "clinical data"
            case .eventLog:         return "event log"
            case .factoryData:      return "factory data"
            case .security:         return "security service"
            case .securityCommands: return "security commands"
            case .challengeData:    return "challenge data"
            case .certificateData:  return "certificate data"
            case .debug:            return "debug service"
            case .bleLogin:         return "BLE login"
            }
        }
    }

    class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }


    // maximum packet size is 20
    // notified packets are prefixed by 00, 01, 02, ...
    // written packets are prefixed by 00 00, 12 00, 24 00, 36 00, ...
    // data packets end in a sequential Int: 01 00, 02 00, ...
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
    // notify 1482  18 bytes            // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // ending in 01 00
    // notify 177A  15 + 20 bytes       // one-minute reading
    // notify 195A  20-byte packets of recent data ending in a sequential Int
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // ending in 02 00
    // notify 1AB8  20-byte packets of past data ending in a sequential Int
    // notify 1338  10 byte             // ending in 02 00
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
    // notify 1482  18 bytes            // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // ending in 01 00
    // notify 1BEE  20 + 20 bytes       // ending in 01 00
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // ending in 02 00
    // notify 1D24  20 * 10 + 15 bytes
    // notify 1338  10 bytes            // ending in 02 00
    //
    // Shutdown:
    // write  1338  13 bytes            // ending in 03 00
    // notify 1BEE  20 bytes            // ending in 01 00
    // write  1338  13 bytes            // ending in 04 00


    /// Single byte command written to the .securityCommands characteristic 0x2198
    enum SecurityCommand: UInt8, CustomStringConvertible {

        // can be sent sequentially during both the initial activation and when repairing a sensor
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

    /// 13 bytes written to the .patchControl characteristic 0x1338:
    /// - PATCH_CONTROL_COMMAND_SIZE = 7
    /// - a final sequential Int starting by 01 00 since it is enqueued
    enum ControlCommand {
        case historic(Data)       // 1 - CTRL_CMD_HISTORIC
        case backflii(Data)       // 2 - CTRL_CMD_BACKFILL
        case eventLog(Data)       // 3 - CTRL_CMD_EVENTLOG
        case factoryData(Data)    // 4 - CTRL_CMD_FACTORY_DATA
        case shutdownPatch(Data)  // 5 - CTRL_CMD_SHUTDOWN_PATCH
    }

    var buffer: Data = Data()
    var currentControlCommand:  ControlCommand?
    var currentSecurityCommand: SecurityCommand?
    var expectedStreamSize = 0


    // TODO: https://github.com/gui-dos/DiaBLE/discussions/7 - "Libre 3 NFC"

    func parsePatchInfo() {
        if patchInfo.count == 28 {
            log("Libre 3: patch info: \(patchInfo.hexBytes), CRC: \(Data(patchInfo.suffix(2).reversed()).hex), computed CRC: \(patchInfo[2...25].crc16.hex)")
            let wearDuration = patchInfo[8...9]
            maxLife = Int(UInt16(wearDuration))
            // TODO: let warmupTime = patchInfo[10] (0x1E) or patchInfo[11] (0x0F) ?
            log("Libre 3: wear duration: \(maxLife) minutes (\(maxLife.formattedInterval), 0x\(maxLife.hex))")
            // state 04 detected already after 15 minutes, 08 for a detached sensor
            // 05 lasts more than 12 hours, almost 24, before that BLE shuts down
            let sensorState = patchInfo[16]
            // TODO: manage specific Libre 3 states
            state = SensorState(rawValue: sensorState <= 2 ? sensorState: sensorState - 1) ?? .unknown
            log("Libre 3: specific state: \(State(rawValue: sensorState)!.description.lowercased()) (0x\(sensorState.hex)), state: \(state.description.lowercased()) ")
            let serialNumber = Data(patchInfo[17...25])
            serial = serialNumber.string
            log("Libre 3: serial number: \(serialNumber.string) (0x\(serialNumber.hex))")

        }
    }


    func send(securityCommand cmd: SecurityCommand) {
        log("Bluetooth: sending to \(type) \(transmitter!.peripheral!.name!) `\(cmd.description)` command 0x\(cmd.rawValue.hex)")
        currentSecurityCommand = cmd
        transmitter!.write(Data([cmd.rawValue]), for: UUID.securityCommands.rawValue, .withResponse)
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

        case .patchControl:
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

        case .historicalData, .clinicalData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let payload = data.prefix(18)
            let id = UInt16(data.suffix(2))
            log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
            // TODO: the end of the stream is notified by 1338 with 10 bytes ending in 0100 for 195A, 0200 for 1AB8

        case .securityCommands:
            if data.count == 2 {
                expectedStreamSize = Int(data[1] + data[1] / 20 + 1)
                log("\(type) \(transmitter!.peripheral!.name!): expected response size: \(expectedStreamSize) bytes")
            }

        case .challengeData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data

                if buffer.count == expectedStreamSize {

                    let (payload, hexDump) = parsePackets(buffer)
                    log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes (payload: \(payload.count) bytes):\n\(hexDump)")

                    switch currentSecurityCommand {

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
                        send(securityCommand: .getSessionInfo)

                    case .getSessionInfo:
                        log("\(type) \(transmitter!.peripheral!.name!): session info: \(payload.hex)")

                    default:
                        break // currentCommand
                    }

                    buffer = Data()
                    expectedStreamSize = 0
                    currentControlCommand = nil
                    currentSecurityCommand = nil

                }
            }

        default:
            break  // uuid
        }

    }


    // MARK: - Constants


    // Libre3BLESensor
    static let STATE_AUTHENTICATING = 0x5
    static let STATE_AUTHORIZING    = 0x8


    // Android MSLibre3Constants
    static let LIBRE3_HISTORIC_LIFECOUNT_INTERVAL = 5
    static let LIBRE3_MAX_HISTORIC_READING_IN_PACKET = 10
    static let HISTORIC_POINT_LATENCY = 17
    static let LIBRE3_DQERROR_MAX = 0xFFFF
    static let LIBRE3_DQERROR_DQ              = 0x8000  // 32768
    static let LIBRE3_DQERROR_SENSOR_TOO_HOT  = 0xA000  // 40960
    static let LIBRE3_DQERROR_SENSOR_TOO_COLD = 0xC000  // 49152
    static let LIBRE3_DQERROR_OUTLIER_FILTER_DELTA = 2
    static let LIBRE3_SENSOR_CONDITION_OK = 0
    static let LIBRE3_SENSOR_CONDITION_INVALID = 1
    static let LIBRE3_SENSOR_CONDITION_ESA_CHECK = 2


    // Libre3.libre3DPCRLInterface
    static let ABT_NO_ERROR = 0x0
    static let ABT_ERR3_TIME_CHANGE = 0x2e
    static let ABT_ERR3_SENSOR_EXPIRED = 0x33
    static let ABT_ERR3_SENSOR_RSSI_ERROR = 0x39
    static let ABT_ERR3_BLE_TURNED_OFF = 0x4b
    static let ABT_ERR3_REPLACE_SENSOR_ERROR = 0x16d
    static let ABT_ERR3_SENSOR_FALL_OUT_ERROR = 0x16e
    static let ABT_ERR3_INCOMPATIBLE_SENSOR_TYPE_ERROR = 0x16f
    static let ABT_ERR3_SENSOR_CAL_CODE_ERROR = 0x170
    static let ABT_ERR3_SENSOR_DYNAMIC_DATA_CRC_ERROR = 0x171
    static let ABT_ERR3_SENSOR_FACTORY_DATA_CRC_ERROR = 0x172
    static let ABT_ERR3_SENSOR_LOG_DATA_CRC_ERROR = 0x173
    static let ABT_ERR3_SENSOR_NOT_YOURS_ERROR = 0x174
    static let ABT_ERR3_REALTIME_RESULT_DQ_ERROR = 0x175
    static let ABT_ERR3_SENSOR_ESA_DETECTED = 0x17c
    static let ABT_ERR3_SENSOR_NOT_IN_GLUCOSE_MEASUREMENT_STATE = 0x181
    static let ABT_ERR3_BLE_PACKET_ERROR = 0x182
    static let ABT_ERR3_INVALID_DATA_SIZE_ERROR = 0x183
    static let ABT_ERR9_LIB_NOT_INITIALIZED_ERROR = 0x3d6
    static let ABT_ERR9_MEMORY_SIZE_ERROR = 0x3d7
    static let ABT_ERR9_NV_MEMORY_CRC_ERROR = 0x3da
    static let ABT_ERROR_DATA_BYTES = 0x8
    static let LIBRE3_DP_LIBRARY_PARSE_ERROR = ~0x0
    static let NFC_ACTIVATION_COMMAND_PAYLOAD_SIZE = 0xa
    static let PATCH_CONTROL_BACKFILL_GREATER_SIZE = 0xb
    static let ABT_HISTORICAL_POINTS_PER_NOTIFICATION = 0x6
    static let LIB3_RECORD_ORDER_NEWEST_TO_OLDEST = 0x0
    static let LIB3_RECORD_ORDER_OLDEST_TO_NEWEST = 0x1
    static let PATCH_CONTROL_COMMAND_SIZE = 0x7
    static let PATCH_NFC_EVENT_LOG_NUM_EVENTS = 0x3
    static let ABT_EVENT_LOGS_PER_NOTIFICATION = 0x2
    static let ABT_ERR10_INVALID_USER = 0x582
    static let ABT_ERR10_DUPLICATE_USER = 0x596
    static let ABT_ERR10_INVALID_TOKEN = 0x5a6
    static let ABT_ERR10_INVALID_DEVICE = 0x5aa
    static let ABT_ERR0_BLE_TURNED_OFF = 0x1f7
    static let SCRATCH_PAD_BUFFER_SIZE = 0x400
    static let CRL_NV_MEMORY_SIZE = 0x400
    static let LIBRE3_DEFAULT_WARMUP_TIME = 0x3c
    static let MAX_SERIAL_NUMBER_SIZE = 0xf


}


// MARK: - PacketLogger logs

// Written to the .certificationData 0x23FA characteristic after the commands 01 and 02 during both activation and repairing a sensor:

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
