import SwiftUI

struct DurationComponentPicker: View {
    let title: String
    @Binding var selection: Int
    let values: ClosedRange<Int>

    var body: some View {
        VStack {
            Text(title)
                .font(.headline)

            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(value.formatted(.number.precision(.integerLength(2))))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
        }
        .frame(maxWidth: .infinity)
    }
}
