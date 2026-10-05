import Foundation
import HomewardCore

/// Cities on the route map, named by their airport-style codes.
struct Place: Hashable {
    let code: String
    let city: String
    let lon: Double
    let lat: Double

    static let all: [String: Place] = [
        "LON": Place(code: "LON", city: "London", lon: -0.13, lat: 51.5),
        "PAR": Place(code: "PAR", city: "Paris", lon: 2.35, lat: 48.86),
        "NYC": Place(code: "NYC", city: "New York", lon: -74, lat: 40.7),
        "YYZ": Place(code: "YYZ", city: "Toronto", lon: -79.4, lat: 43.7),
        "LOS": Place(code: "LOS", city: "Lagos", lon: 3.38, lat: 6.52),
        "ACC": Place(code: "ACC", city: "Accra", lon: -0.19, lat: 5.6),
        "NBO": Place(code: "NBO", city: "Nairobi", lon: 36.82, lat: -1.29),
        "BOM": Place(code: "BOM", city: "Mumbai", lon: 72.88, lat: 19.08),
    ]

    static func origin(for currency: Currency) -> Place {
        switch currency {
        case .EUR: return all["PAR"]!
        case .USD: return all["NYC"]!
        case .CAD: return all["YYZ"]!
        default: return all["LON"]!
        }
    }

    static func destination(for country: Country) -> Place {
        switch country {
        case .nigeria: return all["LOS"]!
        case .ghana: return all["ACC"]!
        case .kenya: return all["NBO"]!
        case .india: return all["BOM"]!
        }
    }
}

/// Land as a dot matrix: 117×50 cells of 1.6° from 100°W/62°N, packed six bits per character.
/// Generated from Natural Earth 1:50m land (public domain).
enum LandMask {
    static let lon0 = -100.0, lat1 = 62.0, step = 1.6, cols = 117, rows = 50
    static let packed = "-APEAPgAAAA_z_______gB9AAIAAAAH-M______8APjAAAAAAA7w_______wA_4AAAAAGAtf_______4H_gAAAABwLD________5__AAAAAzA__________P_8AAAAG8____________-gAAAAHf___________wHAAAAAP____________koAAAAD____________-QAAAAAP__8n4______-QAAAAAB-z_A-f______gAAAAAH-HPwB4______wAAAAAAfgE_OPj_____-AAAAAAH6ICf_8______AAAAAAA_AMZ__j_____8AAAAAABD8AFf_______AAAAAAAP_gAL_______gAAAAAAD_8AAf______4AAAAAAA__88D______hAAAAAAAH_____7____AMAAAAAAB______P___wAgAAAAAAf____P83__-AEAAAAAAH____9_wI__wAEAAAAAB_____n_8D_-ASAAAAAAf____-__gf_wwEAAAAAB_____z_8Af_GAGAAAAAP____-P_AD-_wAAAAAAB_____5_gAfgPwAAAAAAP_____n4ADwA-AAAAAAB_____-4AAOAAwAAAAAAP_____4EABwAGBwAAAAA______OAAOAAK_8AAAAD______wAAoAAv_wAAAAf_____8AABAAA__AAAAA_n____gAAAAAH__gAAAAAX___4AAAAAB__8AAAAAA___-AAAAAAP__wAAAAAH___gAAAAAD___AAAAAA___4AAAAAAf__uAAAAAH__-AAAAAAD____AAAAAf__gAAAAAA____-AAAAB__4AAAAAAD____wAAAAP__gAAAAAAP___-AAAAB__8AAAAAAB____gAAAAP__gAAAAAAH___8AAAAA__8AAAAAAA____AAAAAP__gAAAAAAD___4AAAAB__-EAAAAAAP___AAAAAf__jgAAA"

    static let points: [(lon: Double, lat: Double)] = {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var bits: [Bool] = []
        bits.reserveCapacity(packed.count * 6)
        for ch in packed {
            let value = alphabet.firstIndex(of: ch) ?? 0
            for shift in stride(from: 5, through: 0, by: -1) { bits.append((value >> shift) & 1 == 1) }
        }
        var result: [(lon: Double, lat: Double)] = []
        for row in 0..<rows {
            for col in 0..<cols where row * cols + col < bits.count && bits[row * cols + col] {
                result.append((lon0 + Double(col) * step, lat1 - Double(row) * step))
            }
        }
        return result
    }()
}
