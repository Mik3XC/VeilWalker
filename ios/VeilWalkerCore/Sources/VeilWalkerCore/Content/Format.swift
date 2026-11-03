import Foundation

/// Number formatting that matches Android's `%,d` / `%.1f` in the en-US locale, independent of the phone's locale,
/// so badge text, cards and the brag card read the same on both apps.
public enum Fmt {
    /// 1234567 → "1,234,567".
    public static func grouped(_ n: Int64) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    public static func grouped(_ n: Int) -> String { grouped(Int64(n)) }

    /// Fixed decimals with a "." separator: fixed(3.14159, 1) → "3.1".
    public static func fixed(_ v: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }
}

/// `[##########..........] 42.0%`: progress as text, legible even at fractions of a percent.
public enum Ascii {
    public static func bar(_ fraction: Double, width: Int = 22) -> String {
        let f = min(max(fraction.isNaN ? 0 : fraction, 0), 1)
        // At least one '#' once anything has been walked, so day one isn't an empty bar.
        let filled = f > 0 ? max(1, Int(f * Double(width))) : 0
        return "[" + String(repeating: "#", count: filled) + String(repeating: ".", count: width - filled) + "] "
            + Fmt.fixed(f * 100, 1) + "%"
    }

    /// The bar without its percentage: `[####......]`.
    public static func barOnly(_ fraction: Double, width: Int = 22) -> String {
        String(bar(fraction, width: width).prefix(width + 2))
    }
}
