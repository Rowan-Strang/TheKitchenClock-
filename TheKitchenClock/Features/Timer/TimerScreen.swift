import SwiftUI
import UIKit

struct TimerScreen: View {
    @State private var viewModel = TimerViewModel()
    @State private var isPresentingDurationEditor = false
    @State private var isConfirmingPause = false
    @State private var isConfirmingReset = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)

                VStack {
                    Text(viewModel.state.title)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                        .accessibilityAddTraits(viewModel.isRunning ? .updatesFrequently : [])

                    CountdownDisplay(text: viewModel.displayText)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                if !viewModel.isRunning {
                    Button(viewModel.primaryActionTitle, action: viewModel.start)
                        .frame(maxWidth: .infinity, minHeight: 128)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint(primaryActionHint)
                }
            }
            .padding()
            .navigationTitle("Kitchen Clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isRunning {
                        Button("Pause", systemImage: "pause.fill") {
                            isConfirmingPause = true
                        }

                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            isConfirmingReset = true
                        }
                    } else {
                        Button("Edit Duration", systemImage: "slider.horizontal.3") {
                            isPresentingDurationEditor = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingDurationEditor) {
            DurationEditor(duration: viewModel.selectedDuration, onSave: viewModel.configure)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Pause timer?", isPresented: $isConfirmingPause, titleVisibility: .visible) {
            Button("Pause Timer", action: viewModel.pause)
        } message: {
            Text("The countdown will stop and can be resumed later.")
        }
        .confirmationDialog("Reset timer?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset Timer", role: .destructive, action: viewModel.reset)
        } message: {
            Text("The timer will return to its full configured duration.")
        }
        .onAppear {
            viewModel.refresh()
            updateIdleTimerState()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, _ in
            viewModel.refresh()
            updateIdleTimerState()
        }
        .onChange(of: viewModel.isRunning) { _, _ in
            updateIdleTimerState()
        }
    }

    private var primaryActionHint: String {
        switch viewModel.state {
        case .ready:
            "Starts the configured timer."
        case .paused:
            "Continues the paused timer."
        case .finished:
            "Starts the same duration again."
        case .running:
            ""
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .ready, .paused:
            .secondary
        case .running:
            .green
        case .finished:
            .orange
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = viewModel.isRunning && scenePhase == .active
    }
}

#Preview("iPhone") {
    TimerScreen()
}

#Preview("iPad", traits: .fixedLayout(width: 1_024, height: 768)) {
    TimerScreen()
}
