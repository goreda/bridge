import Foundation
/// Field sanitization and deterministic number formatting for TSV output.
public enum TSVEscape {
    /// Makes any string safe as a single TSV field: backslash-escapes
    /// backslash, tab, CR, LF and other C0/DEL control characters, so a
    /// hostile or odd backend name can never split a row or a column.
    /// Output is pure printable ASCII plus untouched non-control scalars.
    public static func sanitize(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u{%02X}", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

public enum TSVFormat {
    /// Locale-independent shortest round-trip decimal: Swift's Double
    /// description always uses '.' and the minimal digits that parse back
    /// to the identical bit pattern with Double(_:). It never contains
    /// tabs or newlines. Exponent notation ("1e-07") round-trips too.
    public static func double(_ v: Double) -> String {
        String(v)
    }

    public static func field(_ v: Double?) -> String {
        v.map(double) ?? "NA"
    }

    public static func field(_ v: Int?) -> String {
        v.map(String.init) ?? "NA"
    }
}
