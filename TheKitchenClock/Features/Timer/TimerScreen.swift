import SwiftUI
import UIKit

struct TimerScreen: View {
    @State private var viewModel = TimerViewModel()
    @State private var isPresentingDurationEditor = false
    @State private var isPresentingPresets = false
    @State private var isConfirmingReset = false
    @State private var isPresentingInvalidTimerLinkAlert = false
    @State private var isPresentingActiveTimerLinkAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    Spacer(minLength: 0)

                    VStack {
                        if let completedCycleDisplayText = viewModel.completedCycleDisplayText {
                            CountdownDisplay(
                                text: viewModel.displayText,
                                fontScale: 2,
                                accessibilityLabel: "\(viewModel.displayText) remaining in the next cycle"
                            )

                            CountdownDisplay(
                                text: completedCycleDisplayText,
                                accessibilityLabel: "Previous cycle complete"
                            )
                        } else {
                            CountdownDisplay(text: viewModel.displayText)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    if viewModel.shouldShowStartControl {
                        RepeatStartButton(
                            title: viewModel.primaryActionTitle,
                            hint: primaryActionHint,
                            onStart: viewModel.start,
                            onEnableRepeatAndStart: viewModel.enableRepeatAndStart
                        )
                    }
                }
                .padding()

                if viewModel.isAwaitingCompletionAcknowledgement {
                    RepeatCycleAcknowledgement(onAcknowledge: viewModel.acknowledgeCompletion)
                }
            }
            .toolbar {
                if viewModel.shouldShowToolbarControls {
                    if viewModel.isRunning {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Reset", systemImage: "arrow.counterclockwise") {
                                isConfirmingReset = true
                            }
                            .confirmationDialog("Reset timer?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                                Button("Reset Timer", role: .destructive, action: viewModel.reset)
                            } message: {
                                Text("The timer will return to its full configured duration.")
                            }
                        }
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Presets", systemImage: "bookmark") {
                                isPresentingPresets = true
                            }
                        }
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !viewModel.isRunning {
                            Button("Edit Duration", systemImage: "slider.horizontal.3") {
                                isPresentingDurationEditor = true
                            }
                        }

                        if viewModel.isRunning || viewModel.isRepeatEnabled {
                            Button(
                                viewModel.isRepeatEnabled ? "Turn Repeat Off" : "Turn Repeat On",
                                systemImage: viewModel.isRepeatEnabled ? "repeat.1" : "repeat",
                                action: viewModel.toggleRepeat
                            )
                        }
                    }
                }
            }
        }
        .modifier(AlarmShakeEffect(isActive: viewModel.isAwaitingCompletionAcknowledgement))
        .statusBarHidden(viewModel.isAwaitingCompletionAcknowledgement)
        .sheet(isPresented: $isPresentingDurationEditor) {
            DurationEditor(duration: viewModel.selectedDuration, onSave: viewModel.configure)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isPresentingPresets) {
            PresetsSheet(
                presets: viewModel.presets,
                selectedDuration: viewModel.selectedDuration,
                onSelect: viewModel.configure,
                onSaveSelectedDuration: viewModel.saveSelectedDurationAsPreset,
                onRemove: viewModel.removePreset
            )
            .presentationDetents([.large])
        }
        .alert("Couldn’t Open Timer", isPresented: $isPresentingInvalidTimerLinkAlert) {
        } message: {
            Text("Use a link in the format kitchenclock://timer?seconds=30.")
        }
        .alert("Timer Already Active", isPresented: $isPresentingActiveTimerLinkAlert) {
        } message: {
            Text("Reset the running timer before opening another timer link.")
        }
        .onOpenURL(perform: handleIncomingURL)
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
    }

    private var primaryActionHint: String {
        switch viewModel.state {
        case .ready:
            "Starts the configured timer."
        case .finished:
            "Starts the same duration again."
        case .running:
            ""
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
    }

    private func updateApplicationActivity() {
        if scenePhase == .active {
            viewModel.applicationDidBecomeActive()
        } else {
            viewModel.applicationDidBecomeInactive()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        do {
            let request = try TimerLinkParser.parse(url)

            switch viewModel.applyTimerLink(request) {
            case .configured:
                break
            case .rejectedWhileTimerIsActive:
                isPresentingActiveTimerLinkAlert = true
            }
        } catch {
            isPresentingInvalidTimerLinkAlert = true
        }
    }
}

#Preview("iPhone") {
    TimerScreen()
}

#Preview("iPad", traits: .fixedLayout(width: 1_024, height: 768)) {
    TimerScreen()
}
