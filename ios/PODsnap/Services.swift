import SwiftUI
import UIKit
import Vision
import VisionKit

// MARK: - On-device text recognition (Vision). No network, no per-scan cost.

enum OCR {
    static func text(from jpeg: Data) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            guard let cg = UIImage(data: jpeg)?.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { return "" }
            let obs = request.results ?? []
            // Vision's origin is bottom-left: read top-to-bottom, then left-to-right.
            let sorted = obs.sorted {
                let dy = $0.boundingBox.midY - $1.boundingBox.midY
                return abs(dy) > 0.01 ? dy > 0 : $0.boundingBox.minX < $1.boundingBox.minX
            }
            return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

// MARK: - Page cleanup

enum PageImage {
    /// Downscale to keep SwiftData small and the PDF light; JPEG 0.7.
    static func normalize(_ image: UIImage, maxSide: CGFloat = 1700) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return out.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Factoring packet PDF: invoice first, then every document page.

enum Packet {
    static func build(load: Load, carrier: Carrier) throws -> URL {
        let W: CGFloat = 612, H: CGFloat = 792, M: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        let hivis = UIColor(red: 1, green: 0.353, blue: 0.122, alpha: 1)
        let soft = UIColor(white: 0.38, alpha: 1)

        func attrs(_ size: CGFloat, _ weight: UIFont.Weight = .regular, _ color: UIColor = .black, align: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let p = NSMutableParagraphStyle(); p.alignment = align
            return [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        }
        @discardableResult
        func draw(_ s: String, _ x: CGFloat, _ y: CGFloat, w: CGFloat, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
            let str = NSAttributedString(string: s, attributes: a)
            let r = str.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
            str.draw(with: CGRect(x: x, y: y, width: w, height: ceil(r.height)), options: [.usesLineFragmentOrigin], context: nil)
            return ceil(r.height)
        }
        let df = DateFormatter(); df.dateStyle = .medium

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            hivis.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: W, height: 8))
            var y = M
            draw(carrier.name.isEmpty ? "Your Carrier LLC" : carrier.name, M, y, w: 340, attrs(20, .bold))
            draw("INVOICE", W / 2, y - 4, w: W / 2 - M, attrs(28, .heavy, align: .right))
            let head = [carrier.address, [carrier.mc.isEmpty ? "" : "MC/DOT \(carrier.mc)", carrier.phone].filter { !$0.isEmpty }.joined(separator: "  ·  "), carrier.email].filter { !$0.isEmpty }
            var hy = y + 28
            for line in head { hy += draw(line, M, hy, w: 340, attrs(10, .regular, soft)) }
            draw("No. \(load.invNo)\nDate \(df.string(from: Date()))\nTerms: Net 30", W / 2, y + 34, w: W / 2 - M, attrs(11, .regular, align: .right))
            y = max(hy, y + 84) + 12

            UIColor.black.setFill(); UIRectFill(CGRect(x: M, y: y, width: W - 2 * M, height: 1.2)); y += 14
            draw("BILL TO", M, y, w: 200, attrs(9, .bold, soft))
            draw("LOAD", W / 2, y, w: 200, attrs(9, .bold, soft)); y += 14
            let bill = [load.broker.isEmpty ? "—" : load.broker, load.brokerMC.isEmpty ? "" : "MC \(load.brokerMC)", load.brokerEmail].filter { !$0.isEmpty }.joined(separator: "\n")
            let bh = draw(bill, M, y, w: W / 2 - M - 12, attrs(11))
            let rows = [("Load #", load.loadNo), ("BOL #", load.bolNo), ("PO #", load.poNo), ("Delivered", df.string(from: load.delivered))].filter { !$0.1.isEmpty }
            var ry = y
            for (k, v) in rows {
                draw(k, W / 2, ry, w: 70, attrs(11, .regular, soft))
                ry += draw(v, W / 2 + 70, ry, w: W / 2 - M - 70, attrs(11))
            }
            y = max(y + bh, ry) + 14

            for (label, val) in [("PICKUP / SHIPPER", load.shipper), ("DELIVERY / CONSIGNEE", load.consignee)] where !val.isEmpty {
                draw(label, M, y, w: 300, attrs(9, .bold, soft)); y += 13
                y += draw(val, M, y, w: W - 2 * M, attrs(11)) + 8
            }

            UIColor.black.setFill(); UIRectFill(CGRect(x: M, y: y, width: W - 2 * M, height: 1.2)); y += 12
            draw("DESCRIPTION", M, y, w: 200, attrs(9, .bold, soft))
            draw("AMOUNT", W / 2, y, w: W / 2 - M, attrs(9, .bold, soft, align: .right)); y += 16
            let charges = [("Linehaul", load.rate), ("Detention", load.detention), ("Lumper (receipt attached)", load.lumper), ("Other", load.other)]
                .filter { Money.parse($0.1) != 0 }
            for (k, v) in charges {
                draw(k, M, y, w: 300, attrs(11))
                y += draw(Money.format(Money.parse(v)), W / 2, y, w: W / 2 - M, attrs(11, .regular, align: .right)) + 2
            }
            if !load.notes.isEmpty { y += draw(load.notes, M, y, w: W - 2 * M - 120, attrs(10, .regular, soft)) }
            y += 6
            UIColor.black.setFill(); UIRectFill(CGRect(x: W / 2, y: y, width: W / 2 - M, height: 2)); y += 10
            draw("TOTAL DUE", W / 2, y, w: 150, attrs(16, .bold))
            draw(Money.format(load.total), W / 2, y, w: W / 2 - M, attrs(16, .bold, align: .right)); y += 40

            if !carrier.remit.isEmpty {
                let a = attrs(11)
                let h = NSAttributedString(string: carrier.remit, attributes: a)
                    .boundingRect(with: CGSize(width: W - 2 * M - 24, height: 400), options: [.usesLineFragmentOrigin], context: nil).height
                UIColor(red: 0.953, green: 0.937, blue: 0.902, alpha: 1).setFill()
                UIRectFill(CGRect(x: M, y: y, width: W - 2 * M, height: h + 34))
                draw("REMIT PAYMENT TO", M + 12, y + 8, w: 300, attrs(9, .bold, soft))
                draw(carrier.remit, M + 12, y + 22, w: W - 2 * M - 24, a)
            }
            let pages = load.sortedPages
            draw("Attached: " + (pages.isEmpty ? "no documents" : pages.map(\.kind).joined(separator: ", ")), M, H - 40, w: 360, attrs(9, .regular, soft))
            draw("Built with PODsnap", W / 2, H - 40, w: W / 2 - M, attrs(9, .regular, soft, align: .right))

            for page in pages {
                guard let img = UIImage(data: page.jpeg) else { continue }
                ctx.beginPage()
                draw("\(page.kind) · Invoice \(load.invNo) · Load \(load.loadNo.isEmpty ? "—" : load.loadNo)", 24, 18, w: W - 48, attrs(9, .regular, soft))
                let box = CGRect(x: 24, y: 36, width: W - 48, height: H - 60)
                let s = min(box.width / img.size.width, box.height / img.size.height)
                let sz = CGSize(width: img.size.width * s, height: img.size.height * s)
                img.draw(in: CGRect(x: (W - sz.width) / 2, y: box.minY, width: sz.width, height: sz.height))
            }
        }
        let safeLoad = load.loadNo.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let name = "Invoice-\(load.invNo)" + (safeLoad.isEmpty ? "" : "-Load-\(safeLoad)") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - VisionKit document camera (edge detection + perspective fix for free)

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let dismiss: () -> Void
        init(onScan: @escaping ([UIImage]) -> Void, dismiss: @escaping () -> Void) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { dismiss() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { dismiss() }
    }
}
