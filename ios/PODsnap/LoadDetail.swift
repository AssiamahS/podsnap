import SwiftUI
import SwiftData
import PhotosUI

/// One load. Wide (Duo unfolded, iPad, landscape Max): paperwork | invoice side by side.
/// Narrow (Duo folded, regular iPhone): a two-step segmented flow. The active step and
/// every field survive a fold because state lives in SwiftData + SceneStorage, not @State.
struct LoadDetail: View {
    @Bindable var load: Load
    @Environment(\.horizontalSizeClass) private var hSize
    @SceneStorage("podsnap.step") private var step: String = "docs"

    var body: some View {
        GeometryReader { geo in
            if hSize == .regular && geo.size.width >= 600 {
                HStack(spacing: 0) {
                    DocsPane(load: load, onFilled: {})
                        .frame(width: min(420, geo.size.width * 0.44))
                    Divider()
                    InvoicePane(load: load)
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Step", selection: $step) {
                        Text("1 · Snap").tag("docs")
                        Text("2 · Invoice").tag("invoice")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    if step == "invoice" {
                        InvoicePane(load: load)
                    } else {
                        DocsPane(load: load, onFilled: { withAnimation { step = "invoice" } })
                    }
                }
            }
        }
        .navigationTitle("Invoice #\(load.invNo)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Paperwork pane

struct DocsPane: View {
    @Bindable var load: Load
    var onFilled: () -> Void
    @Environment(\.modelContext) private var context
    @State private var picks: [PhotosPickerItem] = []
    @State private var showScanner = false
    @State private var status = ""
    @State private var reading = false

    private let grid = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rate con, BOL, POD, lumper. Read on this iPhone — nothing is uploaded.")
                    .font(.footnote).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if DocumentScanner.isAvailable {
                        Button { showScanner = true } label: {
                            Label("Scan pages", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    PhotosPicker(selection: $picks, maxSelectionCount: 8, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                if !load.pages.isEmpty {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(load.sortedPages) { page in
                            PageThumb(page: page) { remove(page) }
                        }
                    }
                }

                Button {
                    Task { await readAll() }
                } label: {
                    HStack {
                        if reading { ProgressView() }
                        Text(reading ? "Reading…" : "Read text & fill invoice")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(load.pages.isEmpty || reading)

                if !status.isEmpty {
                    Text(status).font(.footnote.monospaced()).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("FACTOR-READY CHECK").font(.caption.weight(.heavy)).foregroundStyle(Theme.carbon)
                    Toggle("Receiver signature + date on POD", isOn: $load.chkSignature)
                    Toggle("Every page legible, no cut-off edges", isOn: $load.chkLegible)
                    Toggle("Load # / PO matches rate con", isOn: $load.chkMatch)
                    Toggle("Rate confirmation attached", isOn: $load.chkRateCon)
                }
                .toggleStyle(.switch)
                .font(.subheadline)
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .sheet(isPresented: $showScanner) {
            DocumentScanner { images in add(images) }
                .ignoresSafeArea()
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                add(images)
                picks = []
            }
        }
    }

    private func add(_ images: [UIImage]) {
        var order = (load.pages.map(\.order).max() ?? -1) + 1
        for img in images {
            guard let jpeg = PageImage.normalize(img) else { continue }
            let page = Page(kind: Page.defaultKind(at: load.pages.count), order: order, jpeg: jpeg)
            context.insert(page)
            page.load = load
            order += 1
        }
        try? context.save()
    }

    private func remove(_ page: Page) {
        context.delete(page)
        try? context.save()
    }

    private func readAll() async {
        reading = true
        defer { reading = false }
        var text = ""
        let pages = load.sortedPages
        for (i, page) in pages.enumerated() {
            status = "Reading page \(i + 1) of \(pages.count)…"
            text += "\n" + (await OCR.text(from: page.jpeg))
        }
        let n = Extractor.apply(Extractor.run(text), to: load)
        try? context.save()
        status = n > 0 ? "Filled \(n) field\(n == 1 ? "" : "s"). Check them." : "Couldn't find fields — fill by hand."
        if n > 0 { onFilled() }
    }
}

struct PageThumb: View {
    @Bindable var page: Page
    var onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = UIImage(data: page.jpeg) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
            Menu {
                ForEach(Page.kinds, id: \.self) { k in Button(k) { page.kind = k } }
                Divider()
                Button("Remove page", role: .destructive, action: onDelete)
            } label: {
                Text(page.kind)
                    .font(.caption2.monospaced().weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
            }
            .padding(4)
        }
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.6), lineWidth: 1.5))
    }
}

// MARK: - Invoice pane

struct InvoicePane: View {
    @Bindable var load: Load
    @Environment(\.modelContext) private var context
    @State private var packetURL: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Bill to") {
                TextField("Broker / customer", text: $load.broker)
                TextField("Broker MC", text: $load.brokerMC).keyboardType(.numberPad)
                TextField("AP email", text: $load.brokerEmail)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section("Load") {
                TextField("Load #", text: $load.loadNo).font(.body.monospaced())
                TextField("BOL #", text: $load.bolNo).font(.body.monospaced())
                TextField("PO #", text: $load.poNo).font(.body.monospaced())
                DatePicker("Delivered", selection: $load.delivered, displayedComponents: .date)
                TextField("Shipper / pickup", text: $load.shipper, axis: .vertical).lineLimit(1...4)
                TextField("Consignee / delivery", text: $load.consignee, axis: .vertical).lineLimit(1...4)
            }
            Section("Charges") {
                money("Linehaul", $load.rate)
                money("Detention", $load.detention)
                money("Lumper", $load.lumper)
                money("Other", $load.other)
                TextField("Notes", text: $load.notes)
                HStack {
                    Text("TOTAL DUE").font(.headline.weight(.heavy))
                    Spacer()
                    Text(Money.format(load.total)).font(.title2.monospaced().weight(.semibold))
                }
            }
            Section {
                Button {
                    do {
                        packetURL = try Packet.build(load: load, carrier: .current())
                        error = nil
                    } catch let e {
                        error = e.localizedDescription
                    }
                } label: {
                    Label("Build packet PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let url = packetURL {
                    ShareLink(item: url, subject: Text("Invoice \(load.invNo) — Load \(load.loadNo)"),
                              message: Text("Invoice \(load.invNo) with BOL/POD attached. Amount due \(Money.format(load.total)).")) {
                        Label("Send \(url.lastPathComponent)", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    if load.uncheckedCount > 0 {
                        Text("\(load.uncheckedCount) factor-ready check\(load.uncheckedCount == 1 ? "" : "s") unticked")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
        }
        .onDisappear { try? context.save() }
    }

    private func money(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .frame(maxWidth: 140)
        }
    }
}
