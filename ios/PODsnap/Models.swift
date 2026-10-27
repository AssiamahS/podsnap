import Foundation
import SwiftData

@Model
final class Load {
    var uid: UUID = UUID()
    var invNo: Int = 1001
    var created: Date = Date()

    var broker: String = ""
    var brokerMC: String = ""
    var brokerEmail: String = ""

    var loadNo: String = ""
    var bolNo: String = ""
    var poNo: String = ""
    var delivered: Date = Date()
    var shipper: String = ""
    var consignee: String = ""

    var rate: String = ""
    var detention: String = ""
    var lumper: String = ""
    var other: String = ""
    var notes: String = ""

    var chkSignature: Bool = false
    var chkLegible: Bool = false
    var chkMatch: Bool = false
    var chkRateCon: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Page.load)
    var pages: [Page] = []

    init(invNo: Int) {
        self.invNo = invNo
    }

    var total: Double {
        [rate, detention, lumper, other].map(Money.parse).reduce(0, +)
    }

    var sortedPages: [Page] {
        pages.sorted { $0.order < $1.order }
    }

    var uncheckedCount: Int {
        [chkSignature, chkLegible, chkMatch, chkRateCon].filter { !$0 }.count
    }
}

@Model
final class Page {
    var kind: String = "BOL"
    var order: Int = 0
    @Attribute(.externalStorage) var jpeg: Data = Data()
    var load: Load?

    init(kind: String, order: Int, jpeg: Data) {
        self.kind = kind
        self.order = order
        self.jpeg = jpeg
    }

    static let kinds = ["BOL", "POD", "RATE CON", "LUMPER", "PAGE"]

    static func defaultKind(at index: Int) -> String {
        index < 4 ? kinds[index] : "PAGE"
    }
}

enum Money {
    static func parse(_ s: String) -> Double {
        let cleaned = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned) ?? 0
    }

    static func format(_ v: Double) -> String {
        v.formatted(.currency(code: "USD"))
    }
}

/// The driver's own company, remembered across loads (UserDefaults via @AppStorage keys).
struct Carrier {
    var name: String
    var mc: String
    var address: String
    var phone: String
    var email: String
    var remit: String

    static func current(_ d: UserDefaults = .standard) -> Carrier {
        Carrier(
            name: d.string(forKey: "c_name") ?? "",
            mc: d.string(forKey: "c_mc") ?? "",
            address: d.string(forKey: "c_addr") ?? "",
            phone: d.string(forKey: "c_phone") ?? "",
            email: d.string(forKey: "c_email") ?? "",
            remit: d.string(forKey: "c_remit") ?? ""
        )
    }
}
