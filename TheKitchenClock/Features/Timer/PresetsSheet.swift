import SwiftUI

struct PresetsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presets: [TimerPreset]
    let selectedDuration: Duration
    let onSelect: (Duration) -> Void
    let onSaveSelectedDuration: () -> Void
    let onRemove: (TimerPreset) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Save \(TimerDurationFormatter.string(for: selectedDuration))", action: onSaveSelectedDuration)
                        .disabled(presets.contains { $0.duration == selectedDuration })
                } footer: {
                    Text("Save the currently configured duration for quick reuse.")
                }

                Section("Saved Durations") {
                    ForEach(presets) { preset in
                        HStack {
                            Button(TimerDurationFormatter.string(for: preset.duration)) {
                                onSelect(preset.duration)
                                dismiss()
                            }

                            Spacer()

                            Button("Remove", role: .destructive) {
                                onRemove(preset)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

#Preview {
    PresetsSheet(
        presets: [.defaultPreset, TimerPreset(duration: .seconds(75))],
        selectedDuration: .seconds(30),
        onSelect: { _ in },
        onSaveSelectedDuration: {},
        onRemove: { _ in }
    )
}
