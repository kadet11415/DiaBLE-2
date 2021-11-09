import Foundation

//
// Some notes on the Libre Pro still to be verified
//
//
// https://github.com/bubbledevteam/bubble-client-swift/blob/master/BubbleClient/LibrePro.swift
//
//
// 5 + 4 + 13 FRAM blocks readable by ISO commands:
// 0x000:  ( 40, "Header")
// 0x028:  ( 32, "Footer")
// 0x048:  (104, "Body")
//
// header[4]: sensor state
// header[6]: failure error code when state = 06
// header[7...8]: sensor age when failure occurred [0 = unknown]
//
// footer[6...7]: maximum life
//
// body[2...3]:   sensor age
// body[4...5]:   trend index
// body[6...7]:   history index
// body[8...103]: 16 6-byte trend values
//
// The following blocks storing 14 days of historic data (≈ 8 KB) are also readable by B0/B3.
//
// If history index < 32 then read starting from the 22nd block
// else read starting again from the 22nd block: (((index - 32) * 6) + 22 * 8) / 8
//
// blocks 0x0406 - 0x04DD: section ending with the patch table for the commands
//                         A0 A1 A2 A4 A3 ?? E0 E1 E2
//
// The raw value is masked by 0x1FFF and needs a conversion factor of 8.5
//
// Libre Pro memory dump:
// config: 0x1A00, 64
// sram:   0x1C00, 4096


class LibrePro: Sensor {

    // TODO: adapt pasted code from Sensor base class

    override var fram: Data {
        didSet {
            encryptedFram = Data()

            updateCRCReport()
            guard !crcReport.contains("FAILED") else {
                state = .unknown
                return
            }

            if let sensorState = SensorState(rawValue: fram[4]) {
                state = sensorState
            }

            guard fram.count >= 176 else { return }

            age = Int(fram[74]) + Int(fram[75]) << 8                 // body[2...3]
            let startDate = lastReadingDate - Double(age) * 60

            //            initializations = Int(fram[318])

            trend = []
            history = []
            let trendIndex = Int(fram[76]) + Int(fram[77]) << 8      // body[4...5]
            let historyIndex = Int(fram[78]) + Int(fram[79]) << 8    // body[6...7]

            log("DEBUG: Libre Pro: trend index: \(trendIndex), history index: \(historyIndex), started on: \(startDate.shortDateTime)")

            // MARK: - continue adaptation from pasted Sensor base

            //            for i in 0 ... 15 {
            //                var j = trendIndex - 1 - i
            //                if j < 0 { j += 16 }
            //                let offset = 28 + j * 6         // body[4 ..< 100]
            //                let rawValue = readBits(fram, offset, 0, 0xe)
            //                let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1ff
            //                let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            //                let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            //                let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            //                var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            //                let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            //                if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            //                let id = age - i
            //                let date = startDate + Double(age - i) * 60
            //                trend.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
            //            }
            //
            //            // FRAM is updated with a 3 minutes delay:
            //            // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/SensorData.swift
            //
            //            let preciseHistoryIndex = ((age - 3) / 15 ) % 32
            //            let delay = (age - 3) % 15 + 3
            //            var readingDate = lastReadingDate
            //            if preciseHistoryIndex == historyIndex {
            //                readingDate.addTimeInterval(60.0 * -Double(delay))
            //            } else {
            //                readingDate.addTimeInterval(60.0 * -Double(delay - 15))
            //            }
            //
            //            for i in 0 ... 31 {
            //                var j = historyIndex - 1 - i
            //                if j < 0 { j += 32 }
            //                let offset = 124 + j * 6    // body[100 ..< 292]
            //                let rawValue = readBits(fram, offset, 0, 0xe)
            //                let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1ff
            //                let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            //                let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            //                let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            //                var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            //                let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            //                if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            //                let id = age - delay - i * 15
            //                let date = id > -1 ? readingDate - Double(i) * 15 * 60 : startDate
            //                history.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
            //            }


            // Libre Pro: fram[42...43] (footer[2..3]) corresponds to patchInfo[2...3]

            // TODO: with a Libre Pro footer[2...3] = 1000 family = 1 but region = 00 ???
            region = Int(fram[43])

            maxLife = Int(fram[46]) + Int(fram[47]) << 8   // footer[6...7]
            DispatchQueue.main.async {
                self.main?.settings.activeSensorMaxLife = self.maxLife
            }
            //
            //            let i1 = readBits(fram, 2, 0, 3)
            //            let i2 = readBits(fram, 2, 3, 0xa)
            //            let i3 = readBits(fram, 0x150, 0, 8)    // footer[-8]
            //            let i4 = readBits(fram, 0x150, 8, 0xe)
            //            let negativei3 = readBits(fram, 0x150, 0x21, 1) != 0
            //            let i5 = readBits(fram, 0x150, 0x28, 0xc) << 2
            //            let i6 = readBits(fram, 0x150, 0x34, 0xc) << 2
            //
            //            calibrationInfo = CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
            //            DispatchQueue.main.async {
            //                self.main?.settings.activeSensorCalibrationInfo = self.calibrationInfo
            //            }

        }
    }


    static func calibrationInfo(fram: Data) -> CalibrationInfo {
        let b = 14 + 42
        let i1 = readBits(fram, 26, 0, 3)
        let i2 = readBits(fram, 26, 3, 0xa)
        let i3 = readBits(fram, b, 0, 8)
        let i4 = readBits(fram, b, 8, 0xe)
        let negativei3 = readBits(fram, b, 0x21, 1) != 0
        let i5 = readBits(fram, b, 0x28, 0xc) << 2
        let i6 = readBits(fram, b, 0x34, 0xc) << 2

        return CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
    }


    override func detailFRAM() {
        log("\(fram.hexDump(header: "Sensor FRAM:", startingBlock: 0))")
        if crcReport.count > 0 {
            log(crcReport)
            if crcReport.contains("FAILED") {
                if history.count > 0 { // bogus raw data
                    main?.errorStatus("Error while validating sensor data")
                    return
                }
            }
        }
        log("Sensor state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")

        if state == .failure {
            let errorCode = fram[6]
            let failureAge = Int(fram[7]) + Int(fram[8]) << 8
            let failureInterval = failureAge == 0 ? "an unknown time" : "\(failureAge) minutes (\(failureAge.formattedInterval))"
            log("Sensor failure error 0x\(errorCode.hex) (\(decodeFailure(error: errorCode))) at \(failureInterval) after activation.")
        }

        // TODO:
        //        if main.settings.debugLevel > 0 {
        //            log("Sensor factory values: raw minimum threshold: \(fram[330]) (tied to SENSOR_SIGNAL_LOW error, should be 150 for a Libre 1), maximum ADC delta: \(fram[332]) (tied to FILTER_DELTA error, should be 90 for a Libre 1)")
        //        }
        //
        //        if initializations > 0 {
        //            log("Sensor initializations: \(initializations)")
        //        }

        log("Sensor region: \(SensorRegion(rawValue: region)?.description ?? "unknown")\(region != 0 ? " (0x\(region.hex))" : "")")
        if maxLife > 0 {
            log("Sensor maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")
        }
        if age > 0 {
            log("Sensor age: \(age) minutes (\(age.formattedInterval)), started on: \((lastReadingDate - Double(age) * 60).shortDateTime)")
        }
    }


    override func updateCRCReport() {
        if fram.count < 176 {
            crcReport = "NFC: FRAM read did not complete: can't verify CRC"

        } else {
            let headerCRC = UInt16(fram[0...1])
            let footerCRC = UInt16(fram[40...41])
            let bodyCRC   = UInt16(fram[72...73])
            let computedHeaderCRC = crc16(fram[2...39])
            let computedFooterCRC = crc16(fram[42...71])
            let computedBodyCRC   = crc16(fram[74...175])

            var report = "Sensor header CRC16: \(headerCRC.hex), computed: \(computedHeaderCRC.hex) -> \(headerCRC == computedHeaderCRC ? "OK" : "FAILED")"
            report += "\nSensor footer CRC16: \(footerCRC.hex), computed: \(computedFooterCRC.hex) -> \(footerCRC == computedFooterCRC ? "OK" : "FAILED")"
            report += "\nSensor body CRC16: \(bodyCRC.hex), computed: \(computedBodyCRC.hex) -> \(bodyCRC == computedBodyCRC ? "OK" : "FAILED")"

            //            if fram.count >= 344 + 195 * 8 {
            //                let commandsCRC = UInt16(fram[344...345])
            //                let computedCommandsCRC = crc16(fram[346 ..< 344 + 195 * 8])
            //                report += "\nSensor commands CRC16: \(commandsCRC.hex), computed: \(computedCommandsCRC.hex) -> \(commandsCRC == computedCommandsCRC ? "OK" : "FAILED")"
            //            }

            crcReport = report
        }
    }

}
