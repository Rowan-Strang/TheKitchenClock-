import SwiftUI
import UIKit

struct TimerScreen: View {
    @State private var viewModel = TimerViewModel()
    @State private var isPresentingDurationEditor = false
    @State private var isPresentingPresets = false
    @State private var isConfirmingPause = false
    @State private var isConfirmingReset = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)

                VStack {
                    if viewModel.isAwaitingRepeatCycleAcknowledgement {
                        RepeatCycleAcknowledgement(onAcknowledge: viewModel.acknowledgeRepeatCycleCompletion)
                    } else {
                        Text(viewModel.state.title)
                            .font(.headline)
                            .foregroundStyle(statusColor)
                            .accessibilityAddTraits(viewModel.isRunning ? .updatesFrequently : [])

                        if viewModel.isRepeatEnabled {
                            Label("Repeat On", systemImage: "repeat")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        CountdownDisplay(text: viewModel.displayText)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                if !viewModel.isRunning {
                    VStack {
                        RepeatStartButton(
                            title: viewModel.primaryActionTitle,
                            hint: primaryActionHint,
                            onStart: viewModel.start,
                            onToggleRepeatAndStart: viewModel.toggleRepeatAndStart
                        )

                        Text("Press and hold to toggle repeat and restart.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
                    }

                    if viewModel.isRunning || viewModel.state.isPaused {
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            isConfirmingReset = true
                        }
                    }

                    if !viewModel.isRunning && !viewModel.state.isPaused {
                        Button("Presets", systemImage: "bookmark") {
                            isPresentingPresets = true
                        }

                        Button("Edit Duration", systemImage: "slider.horizontal.3") {
                            isPresentingDurationEditor = true
                        }
                    }

                    if viewModel.isRunning || viewModel.isRepeatEnabled {
                        Button(
                            viewModel.isRepeatEnabled ? "Turn Repeat Off" : "Turn Repeat On",
                            systemImage: "repeat",
                            action: viewModel.toggleRepeat
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingDurationEditor) {
            DurationEditor(duration: viewModel.selectedDuration, onSave: viewModel.configure)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $isPresentingPresets) {
            PresetsSheet(
                presets: viewModel.presets,
                selectedDuration: viewModel.selectedDuration,
                onSelect: viewModel.configure,
                onSaveSelectedDuration: viewModel.saveSelectedDurationAsPreset,
                onRemove: viewModel.removePreset
            )
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
            updateApplicationActivity()
            updateIdleTimerState()
        }
        .onDisappear {
            viewModel.applicationDidBecomeInactive()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, _ in
            updateApplicationActivity()
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

    private func updateApplicationActivity() {
        if scenePhase == .active {
            viewModel.applicationDidBecomeActive()
        } else {
            viewModel.applicationDidBecomeInactive()
        }
    }
}

#Preview("iPhone") {
    TimerScreen()
}

#Preview("iPad", traits: .fixedLayout(width: 1_024, height: 768)) {
    TimerScreen()
}
