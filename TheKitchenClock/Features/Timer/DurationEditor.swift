import SwiftUI

struct DurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int

    private let onSave: (Duration) -> Void

    init(duration: Duration, onSave: @escaping (Duration) -> Void) {
        let totalSeconds = duration.components.seconds

        _hours = State(initialValue: Int(totalSeconds / 3_600))
        _minutes = State(initialValue: Int((totalSeconds % 3_600) / 60))
        _seconds = State(initialValue: Int(totalSeconds % 60))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack {
                Text("Set a duration")
                    .font(.title2)
                    .bold()

                Text("Choose hours, minutes, and seconds.")
                    .foregroundStyle(.secondary)

                HStack {
                    DurationComponentPicker(title: "Hours", selection: $hours, values: 0...99)
                    DurationComponentPicker(title: "Minutes", selection: $minutes, values: 0...59)
                    DurationComponentPicker(title: "Seconds", selection: $seconds, values: 0...59)
                }
            }
            .padding()
            .navigationTitle("Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(.seconds(Int64(totalSeconds)))
                        dismiss()
                    }
                    .disabled(totalSeconds == 0)
                }
            }
        }
    }

    private var totalSeconds: Int {
        hours * 3_600 + minutes * 60 + seconds
    }
}

#Preview {
    DurationEditor(duration: .seconds(30), onSave: { _ in })
}
