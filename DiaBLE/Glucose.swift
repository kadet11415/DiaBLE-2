import Foundation


enum GlucoseUnit: String, CustomStringConvertible, CaseIterable, Identifiable {
    case mgdl, mmoll
    var id: String { rawValue}

    var description: String {
        switch self {
        case .mgdl:  return "mg/dL"
        case .mmoll: return "mmol/L"
        }
    }
}


struct Glucose: Identifiable, Codable {

    struct DataQuality: OptionSet, Codable, CustomStringConvertible {

        let rawValue: Int

        static let OK = DataQuality([])

        // lower 9 of 11 bits in the measurement field 0xe/0xb
        static let SD14_FIFO_OVERFLOW  = DataQuality(rawValue: 0x0001)
        /// delta between two successive of 4 filament measurements (1-2, 2-3, 3-4) > fram[332] (Libre 1: 90)
        /// indicates too much jitter in measurement
        static let FILTER_DELTA        = DataQuality(rawValue: 0x0002)
        static let WORK_VOLTAGE        = DataQuality(rawValue: 0x0004)
        static let PEAK_DELTA_EXCEEDED = DataQuality(rawValue: 0x0008)
        static let AVG_DELTA_EXCEEDED  = DataQuality(rawValue: 0x0010)
        /// NFC activity detected during a measurement which was retried since corrupted by NFC power usage
        static let RF                  = DataQuality(rawValue: 0x0020)
        static let REF_R               = DataQuality(rawValue: 0x0040)
        /// measurement result exceeds 0x3FFF (14 bits)
        static let SIGNAL_SATURATED    = DataQuality(rawValue: 0x0080)
        /// 4 times averaged raw reading < fram[330] (minimumThreshold: 150)
        static let SENSOR_SIGNAL_LOW   = DataQuality(rawValue: 0x0100)

        /// as an error code it actually indicates that one or more errors occurred in the
        /// last measurement cycle and is stored in the measurement bit 0x19/0x1 ("hasError")
        static let THERMISTOR_OUT_OF_RANGE = DataQuality(rawValue: 0x0800)

        static let TEMP_HIGH           = DataQuality(rawValue: 0x2000)
        static let TEMP_LOW            = DataQuality(rawValue: 0x4000)
        static let INVALID_DATA        = DataQuality(rawValue: 0x8000)

        var description: String {
            var d = [String: Bool]()
            d["OK"]                  = self == .OK
            d["SD14_FIFO_OVERFLOW"]  = self.contains(.SD14_FIFO_OVERFLOW)
            d["FILTER_DELTA"]        = self.contains(.FILTER_DELTA)
            d["WORK_VOLTAGE"]        = self.contains(.WORK_VOLTAGE)
            d["PEAK_DELTA_EXCEEDED"] = self.contains(.PEAK_DELTA_EXCEEDED)
            d["AVG_DELTA_EXCEEDED"]  = self.contains(.AVG_DELTA_EXCEEDED)
            d["RF"]                  = self.contains(.RF)
            d["REF_R"]               = self.contains(.REF_R)
            d["SIGNAL_SATURATED"]    = self.contains(.SIGNAL_SATURATED)
            d["SENSOR_SIGNAL_LOW"]   = self.contains(.SENSOR_SIGNAL_LOW)
            d["THERMISTOR_OUT_OF_RANGE"] = self.contains(.THERMISTOR_OUT_OF_RANGE)
            d["TEMP_HIGH"]           = self.contains(.TEMP_HIGH)
            d["TEMP_LOW"]            = self.contains(.TEMP_LOW)
            d["INVALID_DATA"]        = self.contains(.INVALID_DATA)
            return "0x\(rawValue.hex): \(d.filter{$1}.keys.joined(separator: ", "))"
        }

    }

    /// id: minutes from sensor start
    let id: Int
    let date: Date
    let rawValue: Int
    let rawTemperature: Int
    let temperatureAdjustment: Int
    let hasError: Bool
    let dataQuality: DataQuality
    let dataQualityFlags: Int
    var value: Int = 0
    var temperature: Double = 0
    var calibration: Calibration? {
        willSet(newCalibration) {
            let slope  = (newCalibration!.slope + newCalibration!.slopeSlope  * Double(rawTemperature) + newCalibration!.offsetSlope) * newCalibration!.extraSlope
            let offset = newCalibration!.offset + newCalibration!.slopeOffset * Double(rawTemperature) + newCalibration!.offsetOffset + newCalibration!.extraOffset
            value = Int(round(slope * Double(rawValue) + offset))
        }
    }
    var source: String = "DiaBLE"

    init(rawValue: Int, rawTemperature: Int = 0, temperatureAdjustment: Int = 0, id: Int = 0, date: Date = Date(), hasError: Bool = false, dataQuality: DataQuality = .OK, dataQualityFlags: Int = 0, calibration: Calibration? = nil) {
        self.id = id
        self.date = date
        self.rawValue = rawValue
        self.value = rawValue / 10
        self.rawTemperature = rawTemperature
        self.temperatureAdjustment = temperatureAdjustment
        self.hasError = hasError
        self.dataQuality = dataQuality
        self.dataQualityFlags = dataQualityFlags
        self.calibration = calibration
    }

    init(bytes: [UInt8], id: Int = 0, date: Date = Date(), calibration: Calibration? = nil) {
        let rawValue = Int(bytes[0]) + Int(bytes[1] & 0x1F) << 8
        let rawTemperature = Int(bytes[3]) + Int(bytes[4] & 0x3F) << 8
        // TODO: temperatureAdjustment
        self.init(rawValue: rawValue, rawTemperature: rawTemperature, id: id, date: date, calibration: calibration)
    }

    init(_ value: Int, temperature: Double = 0, id: Int = 0, date: Date = Date(), dataQuality: Glucose.DataQuality = .OK, source: String = "DiaBLE") {
        self.init(rawValue: value * 10, id: id, date: date, dataQuality: dataQuality)
        self.temperature = temperature
        self.source = source
    }

}


func factoryGlucose(rawGlucose: Glucose, calibrationInfo: CalibrationInfo) -> Glucose {

    guard rawGlucose.id >= 0 && rawGlucose.rawValue > 0 && calibrationInfo != .empty else { return rawGlucose }

    let x: Double = 1000 + 71500
    let y: Double = 1000

    let ca = 0.0009180023
    let cb = 0.0001964561
    let cc = 0.0000007061775
    let cd = 0.00000005283566

    let R = ((Double(rawGlucose.rawTemperature) * x) / Double(rawGlucose.temperatureAdjustment + calibrationInfo.i6)) - y
    let logR = Darwin.log(R)
    let d = pow(logR, 3) * cd + pow(logR, 2) * cc + logR * cb + ca
    let temperature = 1 / d - 273.15


    // https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreMeasurement.swift

    let t1 = [
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3,
        1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3
    ]

    let t2 = [
        0.037744199999999999, 0.037744199999999999, 0.037744199999999999, 0.037744199999999999, 0.037744199999999999, 0.037744199999999999, 0.037744199999999999, 0.037744199999999999,
        0.038121700000000001, 0.038121700000000001, 0.038121700000000001, 0.038121700000000001, 0.038121700000000001, 0.038121700000000001, 0.038121700000000001, 0.038121700000000001,
        0.0385029, 0.0385029, 0.0385029, 0.0385029, 0.0385029, 0.0385029, 0.0385029, 0.0385029,
        0.038887900000000003, 0.038887900000000003, 0.038887900000000003, 0.038887900000000003, 0.038887900000000003, 0.038887900000000003, 0.038887900000000003, 0.038887900000000003,
        0.039276800000000001, 0.039276800000000001, 0.039276800000000001, 0.039276800000000001, 0.039276800000000001, 0.039276800000000001, 0.039276800000000001, 0.039276800000000001,
        0.039669599999999999, 0.039669599999999999, 0.039669599999999999, 0.039669599999999999, 0.039669599999999999, 0.039669599999999999, 0.039669599999999999, 0.039669599999999999,
        0.040066299999999999, 0.040066299999999999, 0.040066299999999999, 0.040066299999999999, 0.040066299999999999, 0.040066299999999999, 0.040066299999999999, 0.040066299999999999,
        0.0404669, 0.0404669, 0.0404669, 0.0404669, 0.0404669, 0.0404669, 0.0404669, 0.0404669,
        0.040871600000000001, 0.040871600000000001, 0.040871600000000001, 0.040871600000000001, 0.040871600000000001, 0.040871600000000001, 0.040871600000000001, 0.040871600000000001,
        0.041280299999999999, 0.041280299999999999, 0.041280299999999999, 0.041280299999999999, 0.041280299999999999, 0.041280299999999999, 0.041280299999999999, 0.041280299999999999,
        0.041693099999999997, 0.041693099999999997, 0.041693099999999997, 0.041693099999999997, 0.041693099999999997, 0.041693099999999997, 0.041693099999999997, 0.041693099999999997,
        0.042110000000000002, 0.042110000000000002, 0.042110000000000002, 0.042110000000000002, 0.042110000000000002, 0.042110000000000002, 0.042110000000000002, 0.042110000000000002,
        0.042531100000000002, 0.042531100000000002, 0.042531100000000002, 0.042531100000000002, 0.042531100000000002, 0.042531100000000002, 0.042531100000000002, 0.042531100000000002,
        0.042956500000000002, 0.042956500000000002, 0.042956500000000002, 0.042956500000000002, 0.042956500000000002, 0.042956500000000002, 0.042956500000000002, 0.042956500000000002,
        0.043386000000000001, 0.043386000000000001, 0.043386000000000001, 0.043386000000000001, 0.043386000000000001, 0.043386000000000001, 0.043386000000000001, 0.043386000000000001,
        0.043819900000000002, 0.043819900000000002, 0.043819900000000002, 0.043819900000000002, 0.043819900000000002, 0.043819900000000002, 0.043819900000000002, 0.043819900000000002,
        0.044258100000000002, 0.044258100000000002, 0.044258100000000002, 0.044258100000000002, 0.044258100000000002, 0.044258100000000002, 0.044258100000000002, 0.044258100000000002,
        0.044700700000000003, 0.044700700000000003, 0.044700700000000003, 0.044700700000000003, 0.044700700000000003, 0.044700700000000003, 0.044700700000000003, 0.044700700000000003,
        0.045147699999999999, 0.045147699999999999, 0.045147699999999999, 0.045147699999999999, 0.045147699999999999, 0.045147699999999999, 0.045147699999999999, 0.045147699999999999,
        0.045599099999999997, 0.045599099999999997, 0.045599099999999997, 0.045599099999999997, 0.045599099999999997, 0.045599099999999997, 0.045599099999999997, 0.045599099999999997,
        0.046055100000000002, 0.046055100000000002, 0.046055100000000002, 0.046055100000000002, 0.046055100000000002, 0.046055100000000002, 0.046055100000000002, 0.046055100000000002,
        0.0465157, 0.0465157, 0.0465157, 0.0465157, 0.0465157, 0.0465157, 0.0465157, 0.0465157,
        0.046980800000000003, 0.046980800000000003, 0.046980800000000003, 0.046980800000000003, 0.046980800000000003, 0.046980800000000003, 0.046980800000000003, 0.046980800000000003,
        0.047450600000000002, 0.047450600000000002, 0.047450600000000002, 0.047450600000000002, 0.047450600000000002, 0.047450600000000002, 0.047450600000000002, 0.047450600000000002,
        0.047925200000000001, 0.047925200000000001, 0.047925200000000001, 0.047925200000000001, 0.047925200000000001, 0.047925200000000001, 0.047925200000000001, 0.047925200000000001,
        0.0484044, 0.0484044, 0.0484044, 0.0484044, 0.0484044, 0.0484044, 0.0484044, 0.0484044,
        0.048888399999999999, 0.048888399999999999, 0.048888399999999999, 0.048888399999999999, 0.048888399999999999, 0.048888399999999999, 0.048888399999999999, 0.048888399999999999,
        0.049377299999999999, 0.049377299999999999, 0.049377299999999999, 0.049377299999999999, 0.049377299999999999, 0.049377299999999999, 0.049377299999999999, 0.049377299999999999,
        0.049871100000000002, 0.049871100000000002, 0.049871100000000002, 0.049871100000000002, 0.049871100000000002, 0.049871100000000002, 0.049871100000000002, 0.049871100000000002,
        0.050369799999999999, 0.050369799999999999, 0.050369799999999999, 0.050369799999999999, 0.050369799999999999, 0.050369799999999999, 0.050369799999999999, 0.050369799999999999,
        0.050873500000000002, 0.050873500000000002, 0.050873500000000002, 0.050873500000000002, 0.050873500000000002, 0.050873500000000002, 0.050873500000000002, 0.050873500000000002,
        0.051382299999999999, 0.051382299999999999, 0.051382299999999999, 0.051382299999999999, 0.051382299999999999, 0.051382299999999999, 0.051382299999999999, 0.051382299999999999,
        0.051896100000000001, 0.051896100000000001, 0.051896100000000001, 0.051896100000000001, 0.051896100000000001, 0.051896100000000001, 0.051896100000000001, 0.051896100000000001,
        0.052415000000000003, 0.052415000000000003, 0.052415000000000003, 0.052415000000000003, 0.052415000000000003, 0.052415000000000003, 0.052415000000000003, 0.052415000000000003,
        0.052939199999999999, 0.052939199999999999, 0.052939199999999999, 0.052939199999999999, 0.052939199999999999, 0.052939199999999999, 0.052939199999999999, 0.052939199999999999,
        0.053468599999999998, 0.053468599999999998, 0.053468599999999998, 0.053468599999999998, 0.053468599999999998, 0.053468599999999998, 0.053468599999999998, 0.053468599999999998,
        0.054003299999999997, 0.054003299999999997, 0.054003299999999997, 0.054003299999999997, 0.054003299999999997, 0.054003299999999997, 0.054003299999999997, 0.054003299999999997,
        0.054543300000000003, 0.054543300000000003, 0.054543300000000003, 0.054543300000000003, 0.054543300000000003, 0.054543300000000003, 0.054543300000000003, 0.054543300000000003,
        0.055088699999999997, 0.055088699999999997, 0.055088699999999997, 0.055088699999999997, 0.055088699999999997, 0.055088699999999997, 0.055088699999999997, 0.055088699999999997,
        0.055639599999999997, 0.055639599999999997, 0.055639599999999997, 0.055639599999999997, 0.055639599999999997, 0.055639599999999997, 0.055639599999999997, 0.055639599999999997,
        0.056196000000000003, 0.056196000000000003, 0.056196000000000003, 0.056196000000000003, 0.056196000000000003, 0.056196000000000003, 0.056196000000000003, 0.056196000000000003,
        0.056758000000000003, 0.056758000000000003, 0.056758000000000003, 0.056758000000000003, 0.056758000000000003, 0.056758000000000003, 0.056758000000000003, 0.056758000000000003,
        0.057325599999999997, 0.057325599999999997, 0.057325599999999997, 0.057325599999999997, 0.057325599999999997, 0.057325599999999997, 0.057325599999999997, 0.057325599999999997,
        0.0578988, 0.0578988, 0.0578988, 0.0578988, 0.0578988, 0.0578988, 0.0578988, 0.0578988,
        0.058477800000000003, 0.058477800000000003, 0.058477800000000003, 0.058477800000000003, 0.058477800000000003, 0.058477800000000003, 0.058477800000000003, 0.058477800000000003,
        0.0590626, 0.0590626, 0.0590626, 0.0590626, 0.0590626, 0.0590626, 0.0590626, 0.0590626,
        0.059653200000000003, 0.059653200000000003, 0.059653200000000003, 0.059653200000000003, 0.059653200000000003, 0.059653200000000003, 0.059653200000000003, 0.059653200000000003,
        0.060249700000000003, 0.060249700000000003, 0.060249700000000003, 0.060249700000000003, 0.060249700000000003, 0.060249700000000003, 0.060249700000000003, 0.060249700000000003,
        0.060852200000000002, 0.060852200000000002, 0.060852200000000002, 0.060852200000000002, 0.060852200000000002, 0.060852200000000002, 0.060852200000000002, 0.060852200000000002,
        0.0614607, 0.0614607, 0.0614607, 0.0614607, 0.0614607, 0.0614607, 0.0614607, 0.0614607,
        0.062075400000000003, 0.062075400000000003, 0.062075400000000003, 0.062075400000000003, 0.062075400000000003, 0.062075400000000003, 0.062075400000000003, 0.062075400000000003,
        0.062696100000000005, 0.062696100000000005, 0.062696100000000005, 0.062696100000000005, 0.062696100000000005, 0.062696100000000005, 0.062696100000000005, 0.062696100000000005,
        0.063323099999999993, 0.063323099999999993, 0.063323099999999993, 0.063323099999999993, 0.063323099999999993, 0.063323099999999993, 0.063323099999999993, 0.063323099999999993,
        0.063956299999999994, 0.063956299999999994, 0.063956299999999994, 0.063956299999999994, 0.063956299999999994, 0.063956299999999994, 0.063956299999999994, 0.063956299999999994,
        0.064595899999999998, 0.064595899999999998, 0.064595899999999998, 0.064595899999999998, 0.064595899999999998, 0.064595899999999998, 0.064595899999999998, 0.064595899999999998,
        0.065241800000000003, 0.065241800000000003, 0.065241800000000003, 0.065241800000000003, 0.065241800000000003, 0.065241800000000003, 0.065241800000000003, 0.065241800000000003,
        0.0658942, 0.0658942, 0.0658942, 0.0658942, 0.0658942, 0.0658942, 0.0658942, 0.0658942,
        0.066553200000000007, 0.066553200000000007, 0.066553200000000007, 0.066553200000000007, 0.066553200000000007, 0.066553200000000007, 0.066553200000000007, 0.066553200000000007,
        0.067218700000000006, 0.067218700000000006, 0.067218700000000006, 0.067218700000000006, 0.067218700000000006, 0.067218700000000006, 0.067218700000000006, 0.067218700000000006,
        0.067890900000000004, 0.067890900000000004, 0.067890900000000004, 0.067890900000000004, 0.067890900000000004, 0.067890900000000004, 0.067890900000000004, 0.067890900000000004,
        0.0685698, 0.0685698, 0.0685698, 0.0685698, 0.0685698, 0.0685698, 0.0685698, 0.0685698,
        0.069255499999999998, 0.069255499999999998, 0.069255499999999998, 0.069255499999999998, 0.069255499999999998, 0.069255499999999998, 0.069255499999999998, 0.069255499999999998,
        0.069948099999999999, 0.069948099999999999, 0.069948099999999999, 0.069948099999999999, 0.069948099999999999, 0.069948099999999999, 0.069948099999999999, 0.069948099999999999,
        0.070647500000000002, 0.070647500000000002, 0.070647500000000002, 0.070647500000000002, 0.070647500000000002, 0.070647500000000002, 0.070647500000000002, 0.070647500000000002,
        0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001, 0.071354000000000001,
        0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996, 0.072067599999999996,
        0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997, 0.072788199999999997,
        0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001, 0.073516100000000001,
        0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006, 0.074251300000000006,
        0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999, 0.074993799999999999,
        0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997, 0.075743699999999997,
        0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005, 0.076501200000000005,
        0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993, 0.077266199999999993,
        0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005, 0.078038800000000005,
        0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006, 0.078819200000000006,
        0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995, 0.079607399999999995,
        0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003, 0.080403500000000003,
        0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002, 0.081207500000000002,
        0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998, 0.082019599999999998,
        0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005, 0.082839800000000005,
        0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998, 0.083668199999999998,
        0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994, 0.084504899999999994,
        0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006, 0.085349900000000006,
        0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999, 0.086203399999999999,
        0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004, 0.087065500000000004,
        0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003, 0.087936100000000003,
        0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006, 0.088815500000000006,
        0.089703599999999994, 0.089703599999999994, 0.089703599999999994, 0.089703599999999994, 0.089703599999999994, 0.089703599999999994, 0.089703599999999994, 0.089703599999999994,
        0.090600700000000006, 0.090600700000000006, 0.090600700000000006, 0.090600700000000006, 0.090600700000000006, 0.090600700000000006, 0.090600700000000006, 0.090600700000000006,
        0.091506699999999996, 0.091506699999999996, 0.091506699999999996, 0.091506699999999996, 0.091506699999999996, 0.091506699999999996, 0.091506699999999996, 0.091506699999999996,
        0.092421699999999996, 0.092421699999999996, 0.092421699999999996, 0.092421699999999996, 0.092421699999999996, 0.092421699999999996, 0.092421699999999996, 0.092421699999999996,
        0.093345999999999998, 0.093345999999999998, 0.093345999999999998, 0.093345999999999998, 0.093345999999999998, 0.093345999999999998, 0.093345999999999998, 0.093345999999999998,
        0.094279399999999999, 0.094279399999999999, 0.094279399999999999, 0.094279399999999999, 0.094279399999999999, 0.094279399999999999, 0.094279399999999999, 0.094279399999999999,
        0.095222200000000007, 0.095222200000000007, 0.095222200000000007, 0.095222200000000007, 0.095222200000000007, 0.095222200000000007, 0.095222200000000007, 0.095222200000000007,
        0.096174399999999993, 0.096174399999999993, 0.096174399999999993, 0.096174399999999993, 0.096174399999999993, 0.096174399999999993, 0.096174399999999993, 0.096174399999999993,
        0.097136200000000006, 0.097136200000000006, 0.097136200000000006, 0.097136200000000006, 0.097136200000000006, 0.097136200000000006, 0.097136200000000006, 0.097136200000000006,
        0.0981075, 0.0981075, 0.0981075, 0.0981075, 0.0981075, 0.0981075, 0.0981075, 0.0981075,
        0.099088599999999999, 0.099088599999999999, 0.099088599999999999, 0.099088599999999999, 0.099088599999999999, 0.099088599999999999, 0.099088599999999999, 0.099088599999999999,
        0.1000795, 0.1000795, 0.1000795, 0.1000795, 0.1000795, 0.1000795, 0.1000795, 0.1000795,
        0.1010803, 0.1010803, 0.1010803, 0.1010803, 0.1010803, 0.1010803, 0.1010803, 0.1010803,
        0.1020911, 0.1020911, 0.1020911, 0.1020911, 0.1020911, 0.1020911, 0.1020911, 0.1020911,
        0.103112, 0.103112, 0.103112, 0.103112, 0.103112, 0.103112, 0.103112, 0.103112,
        0.1041431, 0.1041431, 0.1041431, 0.1041431, 0.1041431, 0.1041431, 0.1041431, 0.1041431,
        0.1051846, 0.1051846, 0.1051846, 0.1051846, 0.1051846, 0.1051846, 0.1051846, 0.1051846,
        0.10623639999999999, 0.10623639999999999, 0.10623639999999999, 0.10623639999999999, 0.10623639999999999, 0.10623639999999999, 0.10623639999999999, 0.10623639999999999,
        0.1072988, 0.1072988, 0.1072988, 0.1072988, 0.1072988, 0.1072988, 0.1072988, 0.1072988,
        0.1083718, 0.1083718, 0.1083718, 0.1083718, 0.1083718, 0.1083718, 0.1083718, 0.1083718,
        0.1094555, 0.1094555, 0.1094555, 0.1094555, 0.1094555, 0.1094555, 0.1094555, 0.1094555,
        0.11055, 0.11055, 0.11055, 0.11055, 0.11055, 0.11055, 0.11055, 0.11055,
        0.1116555, 0.1116555, 0.1116555, 0.1116555, 0.1116555, 0.1116555, 0.1116555, 0.1116555,
        0.1127721, 0.1127721, 0.1127721, 0.1127721, 0.1127721, 0.1127721, 0.1127721, 0.1127721,
        0.1138998, 0.1138998, 0.1138998, 0.1138998, 0.1138998, 0.1138998, 0.1138998, 0.1138998,
        0.1150388, 0.1150388, 0.1150388, 0.1150388, 0.1150388, 0.1150388, 0.1150388, 0.1150388,
        0.11618920000000001, 0.11618920000000001, 0.11618920000000001, 0.11618920000000001, 0.11618920000000001, 0.11618920000000001, 0.11618920000000001, 0.11618920000000001,
        0.1173511, 0.1173511, 0.1173511, 0.1173511, 0.1173511, 0.1173511, 0.1173511, 0.1173511,
        0.11852459999999999, 0.11852459999999999, 0.11852459999999999, 0.11852459999999999, 0.11852459999999999, 0.11852459999999999, 0.11852459999999999, 0.11852459999999999,
        0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999, 0.11970989999999999,
        0.120907, 0.120907, 0.120907, 0.120907, 0.120907, 0.120907, 0.120907, 0.120907, 0.120907,
        0.122116, 0.122116, 0.122116, 0.122116, 0.122116, 0.122116, 0.122116, 0.122116, 0.122116,
        0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999, 0.12333719999999999,
        0.1245706, 0.1245706, 0.1245706, 0.1245706, 0.1245706, 0.1245706, 0.1245706, 0.1245706, 0.1245706,
        0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999, 0.12581629999999999,
        0.1270744, 0.1270744, 0.1270744, 0.1270744, 0.1270744, 0.1270744, 0.1270744, 0.1270744, 0.1270744,
        0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999, 0.12834519999999999
    ]

    let g1 = 65 * Double(rawGlucose.rawValue - calibrationInfo.i3) / Double(calibrationInfo.i4 - calibrationInfo.i3)
    let g2 = pow(1.045, 32.5 - temperature)
    let g3 = g1 * g2

    let v1 = t1[calibrationInfo.i2 - 1]
    let v2 = t2[calibrationInfo.i2 - 1]
    let value = Int(round((g3 - v1) / v2))

    var glucose = rawGlucose
    glucose.value = value
    glucose.temperature = temperature

    return glucose
}


struct Calibration: Codable, Equatable {
    var slope: Double = 0.0
    var offset: Double = 0.0
    var slopeSlope: Double = 0.0
    var slopeOffset: Double = 0.0
    var offsetOffset: Double = 0.0
    var offsetSlope: Double = 0.0
    var extraSlope: Double = 1.0
    var extraOffset: Double = 0.0

    enum CodingKeys: String, CodingKey, CustomStringConvertible {
        case slopeSlope   = "slope_slope"
        case slopeOffset  = "slope_offset"
        case offsetOffset = "offset_offset"
        case offsetSlope  = "offset_slope"

        // Pay attention to the inversions:
        // enums are intended to be read as "term + subfix", therefore .slopeOffset = "slope of the offset" => "Offset slope"
        var description: String {
            switch self {
            case .slopeSlope:   return "Slope slope"
            case .slopeOffset:  return "Offset slope"
            case .offsetOffset: return "Offset offset"
            case .offsetSlope:  return "Slope offset"
            }
        }
    }

    static var empty = Calibration()
}


// https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/TrendSymbol.swift

public func trendSymbol(for trend: Double) -> String {
    if trend > 2.0 {
        return "⇈"
    } else if trend > 1.0 {
        return "↑"
    } else if trend > 0.33 {
        return "↗︎"
    } else if trend > -0.33 {
        return "→"
    } else if trend > -1.0 {
        return "↘︎"
    } else if trend > -2.0 {
        return "↓"
    } else {
        return "⇊"
    }
}
