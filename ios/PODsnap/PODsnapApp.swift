import SwiftUI
import SwiftData

@main
struct PODsnapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.hivis)
        }
        .modelContainer(for: [Load.self, Page.self])
    }
}

enum Theme {
    static let hivis = Color(red: 1, green: 0.353, blue: 0.122)
    static let carbon = Color(red: 0.165, green: 0.235, blue: 0.561)
}

/// Sidebar of loads + detail. On the Duo's inner display (regular width) both columns
/// show, and the detail itself splits camera | invoice. Folded, it collapses to a stack.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Load.created, order: .reverse) private var loads: [Load]
    @SceneStorage("podsnap.selectedLoad") private var selectedID: String = ""
    @SceneStorage("podsnap.columns") private var columnsRaw: String = "all"
    @AppStorage("c_next") private var nextInvoice: Int = 1001
    @State private var showCarrier = false

    private var selection: Binding<UUID?> {
        Binding(get: { UUID(uuidString: selectedID) }, set: { selectedID = $0?.uuidString ?? "" })
    }

    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnsRaw == "detail" ? .detailOnly : .all },
            set: { columnsRaw = $0 == .detailOnly ? "detail" : "all" }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columns) {
            List(selection: selection) {
                ForEach(loads) { load in
                    LoadRow(load: load).tag(load.uid as UUID?)
                }
                .onDelete { idx in
                    for i in idx { context.delete(loads[i]) }
                }
            }
            .overlay {
                if loads.isEmpty {
                    ContentUnavailableView("No loads yet", systemImage: "doc.viewfinder", description: Text("Tap + after you deliver."))
                }
            }
            .navigationTitle("PODsnap")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addLoad() } label: { Label("New load", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCarrier = true } label: { Label("Your company", systemImage: "building.2") }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            if let load = loads.first(where: { $0.uid.uuidString == selectedID }) {
                LoadDetail(load: load)
                    .id(load.uid)
            } else {
                ContentUnavailableView {
                    Label("Pick or start a load", systemImage: "truck.box")
                } description: {
                    Text("Scan the signed BOL, check the invoice, send one PDF.")
                } actions: {
                    Button("New load") { addLoad() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showCarrier) { CarrierSheet() }
    }

    private func addLoad() {
        let load = Load(invNo: nextInvoice)
        nextInvoice += 1
        context.insert(load)
        try? context.save()
        selectedID = load.uid.uuidString
    }
}

struct LoadRow: View {
    let load: Load
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("#\(load.invNo)").font(.system(.headline, design: .monospaced))
                Spacer()
                Text(Money.format(load.total)).font(.system(.subheadline, design: .monospaced))
            }
            Text(load.broker.isEmpty ? "No broker yet" : load.broker)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text(load.loadNo.isEmpty ? "Load # —" : "Load \(load.loadNo)")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct CarrierSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("c_name") private var name = ""
    @AppStorage("c_mc") private var mc = ""
    @AppStorage("c_addr") private var addr = ""
    @AppStorage("c_phone") private var phone = ""
    @AppStorage("c_email") private var email = ""
    @AppStorage("c_remit") private var remit = ""
    @AppStorage("c_next") private var next: Int = 1001

    var body: some View {
        NavigationStack {
            Form {
                Section("Your company") {
                    TextField("Carrier name", text: $name)
                    TextField("MC / DOT", text: $mc).keyboardType(.numbersAndPunctuation)
                    TextField("Address", text: $addr, axis: .vertical)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section("Remit to / factor NOA") {
                    TextField("Shown on every invoice", text: $remit, axis: .vertical).lineLimit(2...5)
                }
                Section("Numbering") {
                    Stepper("Next invoice #\(next)", value: $next, in: 1...999_999)
                }
            }
            .navigationTitle("Your company")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
