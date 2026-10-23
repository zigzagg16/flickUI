import flickUI
import SwiftUI

struct SettingsView: View {
    @Binding var settings: DemoSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Edges") {
                    ForEach(FlickEdge.allCases, id: \.self) { edge in
                        Toggle(String(describing: edge).capitalized, isOn: edgeBinding(edge))
                    }
                    Picker("Indicator home", selection: $settings.home) {
                        ForEach(FlickEdge.allCases, id: \.self) { edge in
                            Text(String(describing: edge).capitalized).tag(edge)
                        }
                    }
                    LabeledContent("Home position") {
                        Slider(value: $settings.homePosition, in: 0...1)
                    }
                    Picker("Haptics", selection: $settings.feedback) {
                        ForEach(FeedbackChoice.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }

                Section("Left & right edges") {
                    EdgeAppearanceEditor(appearance: $settings.sides)
                }

                Section {
                    Toggle("Customize top & bottom separately", isOn: $settings.customizesEnds)
                    if settings.customizesEnds {
                        EdgeAppearanceEditor(appearance: $settings.ends)
                    }
                } header: {
                    Text("Top & bottom edges")
                } footer: {
                    Text("Per-edge settings: each group of edges can look and behave differently.")
                }

                Section {
                    Button("Reset", role: .destructive) { settings = DemoSettings() }
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func edgeBinding(_ edge: FlickEdge) -> Binding<Bool> {
        Binding(
            get: { settings.edges.contains(FlickEdgeSet(edge)) },
            set: { isOn in
                if isOn {
                    settings.edges.insert(FlickEdgeSet(edge))
                } else {
                    settings.edges.remove(FlickEdgeSet(edge))
                }
            }
        )
    }
}

struct EdgeAppearanceEditor: View {
    @Binding var appearance: EdgeAppearance

    var body: some View {
        Picker("Indicator", selection: $appearance.indicator) {
            ForEach(IndicatorChoice.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        ColorPicker("Tint", selection: $appearance.tint, supportsOpacity: false)
        Picker("Rows", selection: $appearance.row) {
            ForEach(RowChoice.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        Picker("Background", selection: $appearance.background) {
            Section("Full screen") {
                ForEach(BackgroundChoice.allCases.filter { !$0.isContained }) { Text($0.title).tag($0) }
            }
            Section("Contained") {
                ForEach(BackgroundChoice.allCases.filter(\.isContained)) { Text($0.title).tag($0) }
            }
        }
        Picker("Physics", selection: $appearance.physics) {
            ForEach(PhysicsChoice.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        LabeledContent("Tracking ×\(appearance.trackingRatio, specifier: "%.1f")") {
            Slider(value: $appearance.trackingRatio, in: 1...4, step: 0.5)
        }
        Picker("Boomerang", selection: $appearance.boomerang) {
            ForEach(BoomerangChoice.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        EmphasisEditor(title: "Highlighted item", emphasis: $appearance.highlight)
        EmphasisEditor(title: "Selected item", emphasis: $appearance.selection)
    }
}

struct EmphasisEditor: View {
    let title: String
    @Binding var emphasis: EmphasisChoice

    var body: some View {
        Picker("\(title) effect", selection: $emphasis.effect) {
            ForEach(EffectChoice.allCases) { Text($0.title).tag($0) }
        }
        if emphasis.effect != .none {
            Toggle("Repeat", isOn: $emphasis.repeats)
        }
        Toggle("Filled symbol", isOn: $emphasis.fills)
        Toggle("Tint", isOn: $emphasis.tints)
        if emphasis.tints {
            ColorPicker("\(title) colour", selection: $emphasis.tint, supportsOpacity: false)
        }
    }
}
