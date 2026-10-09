import Foundation

/// A deliberately small, non-identifying system power snapshot.
/// Serial numbers, battery health history and power-source identifiers are
/// never persisted or presented.
struct BatteryPowerSnapshot: Equatable {
    let percentage: Int?
    let isCharging: Bool?
    let isOnExternalPower: Bool?
    let isLowPowerMode: Bool

    static func reported(
        by descriptions: [[String: Any]], lowPowerMode: Bool
    ) -> BatteryPowerSnapshot {
        guard let source = descriptions.first(where: {
            ($0["Type"] as? String) == "InternalBattery" &&
                ($0["Is Present"] as? NSNumber)?.boolValue == true
        }) else {
            return BatteryPowerSnapshot(
                percentage: nil, isCharging: nil,
                isOnExternalPower: nil, isLowPowerMode: lowPowerMode
            )
        }

        let current = source["Current Capacity"] as? NSNumber
        let maximum = source["Max Capacity"] as? NSNumber
        let fraction: Int?
        if let current, let maximum,
           maximum.doubleValue.isFinite, current.doubleValue.isFinite,
           maximum.doubleValue > 0, current.doubleValue >= 0,
           current.doubleValue <= maximum.doubleValue {
            fraction = Int((current.doubleValue / maximum.doubleValue * 100).rounded())
        } else {
            fraction = nil
        }

        let charging = (source["Is Charging"] as? NSNumber)?.boolValue
        let external: Bool?
        switch source["Power Source State"] as? String {
        case "AC Power": external = true
        case "Battery Power": external = false
        default: external = nil
        }

        return BatteryPowerSnapshot(
            percentage: fraction,
            isCharging: charging,
            isOnExternalPower: external,
            isLowPowerMode: lowPowerMode
        )
    }

    static let unavailable = BatteryPowerSnapshot(
        percentage: nil, isCharging: nil,
        isOnExternalPower: nil, isLowPowerMode: false
    )

    var powerLabel: String {
        if isCharging == true { return "Charging" }
        if isOnExternalPower == true { return "Power adapter connected" }
        if isOnExternalPower == false { return "Running on battery" }
        return "Power source not reported"
    }
}
