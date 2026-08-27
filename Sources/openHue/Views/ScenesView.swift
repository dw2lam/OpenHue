import SwiftUI

struct ScenesView: View {
    @EnvironmentObject var model: AppModel

    @State private var isSavePresented = false
    @State private var renameTarget: HueScene?
    @State private var deleteTarget: HueScene?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.readyLights.isEmpty {
                    HueInfoCallout("No lights are connected right now — scenes apply as soon as a bulb reconnects.")
                }

                section("Hue scenes") {
                    ForEach(model.presetScenes) { scene in
                        SceneCard(scene: scene, lights: model.lights) {
                            model.apply(scene: scene)
                        } onApplyTo: { light in
                            model.apply(scene: scene, to: [light])
                        }
                    }
                }

                if model.userScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("My scenes")
                            .font(.title3.weight(.semibold))
                        emptyState
                    }
                } else {
                    section("My scenes") {
                        ForEach(model.userScenes) { scene in
                            SceneCard(scene: scene, lights: model.lights) {
                                model.apply(scene: scene)
                            } onApplyTo: { light in
                                model.apply(scene: scene, to: [light])
                            } onRename: {
                                renameTarget = scene
                            } onDelete: {
                                deleteTarget = scene
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Scenes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isSavePresented = true } label: {
                    Label("Save current as scene…", systemImage: "plus.square.on.square")
                }
                .help("Snapshot the current state of every light as a new scene")
            }
        }
        .sheet(isPresented: $isSavePresented) {
            SceneNameSheet(title: "Save current as scene", prompt: "Snapshots the current state of every light.", initialName: "") { name in
                model.saveCurrentAsScene(named: name)
            }
        }
        .sheet(item: $renameTarget) { scene in
            SceneNameSheet(title: "Rename scene", prompt: nil, initialName: scene.name) { name in
                model.renameScene(id: scene.id, to: name)
            }
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { scene in
            Button("Delete", role: .destructive) { model.deleteScene(id: scene.id) }
        } message: { _ in
            Text("Schedules that use this scene will need a new target.")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No saved scenes yet")
                .font(.headline)
            Text("Set your lights how you like them, then click “Save current as scene…” in the toolbar.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Save current as scene…") { isSavePresented = true }
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4])).foregroundStyle(.quaternary))
    }
}

// MARK: - Card

private struct SceneCard: View {
    let scene: HueScene
    let lights: [HueLight]
    let onApply: () -> Void
    let onApplyTo: (HueLight) -> Void
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var hovering = false

    private var swatchColors: [Color] {
        Array(scene.swatches.prefix(5)).map(\.displayColor)
    }

    private var tint: Color {
        scene.swatches.first?.displayColor ?? .accentColor
    }

    var body: some View {
        Button(action: onApply) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: scene.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(height: 24)
                Spacer(minLength: 0)
                Text(scene.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                swatchStrip
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            if hovering, onRename != nil || onDelete != nil {
                HStack(spacing: 2) {
                    if let onRename {
                        Button(action: onRename) { Image(systemName: "pencil") }
                            .help("Rename")
                    }
                    if let onDelete {
                        Button(action: onDelete) { Image(systemName: "trash") }
                            .help("Delete")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(6)
            }
        }
        .contextMenu {
            Button("Apply", action: onApply)
            if !lights.isEmpty {
                Menu("Apply to…") {
                    ForEach(lights) { light in
                        Button(light.name) { onApplyTo(light) }
                    }
                }
            }
            if onRename != nil || onDelete != nil {
                Divider()
                if let onRename { Button("Rename…", action: onRename) }
                if let onDelete { Button("Delete…", role: .destructive, action: onDelete) }
            }
        }
        .help("Apply “\(scene.name)”")
    }

    private var swatchStrip: some View {
        HStack(spacing: 4) {
            if swatchColors.isEmpty {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 10)
            } else {
                ForEach(Array(swatchColors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(height: 10)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.1)))
                }
            }
        }
    }
}

// MARK: - Name sheet (save / rename)

private struct SceneNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String?
    let onCommit: (String) -> Void

    @State private var name: String

    init(title: String, prompt: String?, initialName: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        self.onCommit = onCommit
        _name = State(initialValue: initialName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let prompt {
                Text(prompt).font(.callout).foregroundStyle(.secondary)
            }
            TextField("Scene name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}
