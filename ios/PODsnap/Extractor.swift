import Foundation

/// Pulls invoice fields out of recognized BOL / POD / rate-con text.
/// Same rules as web/app.js `extract()` so both apps fill the form identically.
struct Extracted {
    var loadNo: String?
    var bolNo: String?
    var poNo: String?
    var rate: String?
    var detention: String?
    var lumper: String?
    var shipper: String?
    var consignee: String?
    var broker: String?
    var brokerEmail: String?
    var brokerMC: String?
    var delivered: Date?
}

enum Extractor {
    private static let id = "((?=[A-Z\\-]*\\d)[A-Z0-9][A-Z0-9\\-]{3,})"
    private static let sep = "\\s*(?:#|no\\.?|num(?:ber)?)?\\s*[:#\\-]?\\s*"

    static func run(_ raw: String, carrier: Carrier = .current()) -> Extracted {
        let text = raw.replacingOccurrences(of: "|", with: " ")
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out = Extracted()

        out.loadNo = group("\\b(?:load|pro|order|trip|confirmation)" + sep + id, in: text)
        out.bolNo = group("\\b(?:b\\s*/?\\s*o\\s*/?\\s*l|bill\\s+of\\s+lading)" + sep + id, in: text)
        out.poNo = group("\\bp\\.?\\s?o\\.?\\s*(?:#|no\\.?|num(?:ber)?)\\s*[:#\\-]?\\s*((?=[A-Z\\-]*\\d)[A-Z0-9][A-Z0-9\\-]{2,})", in: text)

        var best = 0.0
        for (i, line) in lines.enumerated() where matches("(line\\s?haul|total|rate|agreed|carrier pay|amount|flat)", line)
            && !matches("(detention|lumper|fuel tax)", line) {
            let next = i + 1 < lines.count ? lines[i + 1] : ""
            best = max(best, money(line + " " + next).max() ?? 0)
        }
        if best == 0 { best = money(text).filter { $0 >= 100 }.max() ?? 0 }
        if best > 0 { out.rate = String(format: "%.2f", best) }
        for line in lines {
            if out.detention == nil, matches("detention", line), let v = money(line).first { out.detention = String(format: "%.2f", v) }
            if out.lumper == nil, matches("lumper", line), let v = money(line).first { out.lumper = String(format: "%.2f", v) }
        }

        out.shipper = block("\\b(shipper|ship\\s*from|pick\\s*up\\s*(location)?|origin)\\b\\s*(name|info(rmation)?)?", lines)
        out.consignee = block("\\b(consignee|ship\\s*to|receiver|destination|deliver\\s*to)\\b\\s*(name|info(rmation)?)?", lines)
        if let bill = block("\\b(bill\\s*to|broker|freight\\s*charges\\s*bill\\s*to)\\b\\s*(name)?", lines) {
            out.broker = bill.components(separatedBy: "\n").first
        }
        if out.broker == nil {
            let me = carrier.name.lowercased()
            out.broker = lines.first { matches("(logistics|brokerage|freight|transportation)\\b", $0) && (me.isEmpty || !$0.lowercased().contains(me)) }
        }

        let emails = all("[\\w.+\\-]+@[\\w\\-]+\\.[\\w.\\-]+", in: text).filter { $0.lowercased() != carrier.email.lowercased() }
        out.brokerEmail = emails.first { matches("(ap|billing|invoice|accounting|pay)", $0) } ?? emails.first
        let myMC = carrier.mc.filter(\.isNumber)
        out.brokerMC = all("\\bMC\\s*#?\\s*:?\\s*(\\d{5,8})", in: text, group: 1).first { $0 != myMC }

        let dateRe = "\\b(\\d{1,2})[/\\-.](\\d{1,2})[/\\-.](\\d{2,4})\\b"
        if let line = lines.first(where: { matches("deliver|received|arriv", $0) && matches(dateRe, $0) }) ?? lines.first(where: { matches(dateRe, $0) }),
           let parts = groups(dateRe, in: line), parts.count == 3,
           let mo = Int(parts[0]), let da = Int(parts[1]), var yr = Int(parts[2]), (1...12).contains(mo), (1...31).contains(da) {
            if yr < 100 { yr += 2000 }
            out.delivered = Calendar(identifier: .gregorian).date(from: DateComponents(year: yr, month: mo, day: da))
        }
        return out
    }

    /// Fill only the fields the driver hasn't typed. Returns how many were filled.
    @discardableResult
    static func apply(_ e: Extracted, to load: Load) -> Int {
        var n = 0
        func fill(_ kp: ReferenceWritableKeyPath<Load, String>, _ v: String?) {
            guard let v, !v.isEmpty, load[keyPath: kp].trimmingCharacters(in: .whitespaces).isEmpty else { return }
            load[keyPath: kp] = v
            n += 1
        }
        fill(\.loadNo, e.loadNo); fill(\.bolNo, e.bolNo); fill(\.poNo, e.poNo)
        fill(\.rate, e.rate); fill(\.detention, e.detention); fill(\.lumper, e.lumper)
        fill(\.shipper, e.shipper); fill(\.consignee, e.consignee)
        fill(\.broker, e.broker); fill(\.brokerEmail, e.brokerEmail); fill(\.brokerMC, e.brokerMC)
        if let d = e.delivered { load.delivered = d; n += 1 }
        return n
    }

    // MARK: - helpers

    private static let stop = "^(shipper|ship\\s*from|origin|pick\\s*up|consignee|ship\\s*to|receiver|destination|deliver(y)?\\s*(to|location)?|carrier|bill\\s*to|broker|third\\s*party|special|instructions|commodity|weight|pieces|signature|date)\\b"

    private static func block(_ pattern: String, _ lines: [String]) -> String? {
        guard let re = regex(pattern) else { return nil }
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let rest = ns.substring(from: m.range.location + m.range.length)
                .trimmingCharacters(in: CharacterSet(charactersIn: " :#-"))
            var got = rest.isEmpty ? [] : [rest]
            var j = i + 1
            while j < lines.count, got.count < 3, !matches(stop, lines[j]) {
                got.append(lines[j]); j += 1
            }
            if !got.isEmpty { return got.joined(separator: "\n") }
        }
        return nil
    }

    private static func money(_ s: String) -> [Double] {
        all("\\$\\s?(\\d{1,3}(?:,\\d{3})+(?:\\.\\d{2})?|\\d+(?:\\.\\d{2})?)", in: s, group: 1)
            .compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    }

    private static func regex(_ p: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static func matches(_ p: String, _ s: String) -> Bool {
        regex(p)?.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func group(_ p: String, in s: String) -> String? {
        groups(p, in: s)?.first
    }

    private static func groups(_ p: String, in s: String) -> [String]? {
        let ns = s as NSString
        guard let m = regex(p)?.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func all(_ p: String, in s: String, group g: Int = 0) -> [String] {
        let ns = s as NSString
        return (regex(p)?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []).compactMap { m in
            let r = m.range(at: g)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}
