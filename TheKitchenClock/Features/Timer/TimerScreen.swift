import SwiftUI
import UIKit

struct TimerScreen: View {
    @State private var viewModel = TimerViewModel()
    @State private var isPresentingDurationEditor = false
    @State private var isPresentingPresets = false
    @State private var isConfirmingReset = false
    @State private var isPresentingInvalidTimerLinkAlert = false
    @State private var isPresentingActiveTimerLinkAlert = false
    @State private var startFeedbackTrigger = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TimerSurfaceButton(
                isReady: viewModel.state == .ready,
                isStarting: viewModel.isStarting,
                isAwaitingCompletionAcknowledgement: viewModel.isAwaitingCompletionAcknowledgement,
                isAwaitingRepeatCycleAcknowledgement: viewModel.isAwaitingRepeatCycleAcknowledgement,
                accessibilityValue: viewModel.displayText,
                onStart: startTimer,
                onEnableRepeatAndStart: startRepeatingTimer,
                onEnableRepeatFromFinishedOneShot: viewModel.enableRepeatFromFinishedOneShot,
                onAcknowledge: viewModel.acknowledgeCompletion,
                onCancelAlarm: viewModel.cancelAlarm
            ) {
                VStack {
                    Spacer(minLength: 0)

                    VStack {
                        if let completedCycleDisplayText = viewModel.completedCycleDisplayText {
                            CountdownDisplay(
                                text: viewModel.displayText,
                                fontScale: 2,
                                accessibilityLabel: "\(viewModel.displayText) remaining in the next cycle",
                                startFeedbackTrigger: startFeedbackTrigger
                            )

                            CountdownDisplay(
                                text: completedCycleDisplayText,
                                accessibilityLabel: "Previous cycle complete"
                            )
                        } else {
                            CountdownDisplay(
                                text: viewModel.displayText,
                                startFeedbackTrigger: startFeedbackTrigger
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                if viewModel.shouldShowToolbarControls {
                    if viewModel.isRunning {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Reset", systemImage: "arrow.counterclockwise") {
                                isConfirmingReset = true
                            }
                            .confirmationDialog("Reset timer?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                                Button("Reset Timer", role: .destructive) {
                                    Task {
                                        await viewModel.reset()
                                    }
                                }
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
                                systemImage: viewModel.isRepeatEnabled ? "repeat.1" : "repeat"
                            ) {
                                Task {
                                    await viewModel.toggleRepeat()
                                }
                            }
                            .disabled(viewModel.isStarting)
                        }
                    }
                }
            }
        }
        .modifier(AlarmShakeEffect(isActive: viewModel.isAwaitingCompletionAcknowledgement))
        .statusBarHidden(viewModel.isAwaitingCompletionAcknowledgement)
        .sensoryFeedback(.impact(weight: .heavy), trigger: startFeedbackTrigger)
        .sheet(isPresented: $isPresentingDurationEditor) {
            DurationEditor(duration: viewModel.selectedDuration) { duration in
                Task {
                    await viewModel.configure(duration: duration)
                }
            }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isPresentingPresets) {
            PresetsSheet(
                presets: viewModel.presets,
                selectedDuration: viewModel.selectedDuration,
                onSelect: { duration in
                    Task {
                        await viewModel.configure(duration: duration)
                    }
                },
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
        .alert(
            viewModel.alarmIssue?.title ?? "Alarm Not Scheduled",
            isPresented: alarmIssueIsPresented
        ) {
            Button("OK", action: viewModel.dismissAlarmIssue)
        } message: {
            Text(viewModel.alarmIssue?.message ?? "")
        }
        .onOpenURL(perform: handleIncomingURL)
        .onAppear {
            Task {
                await updateApplicationActivity()
            }
            updateIdleTimerState()
        }
        .onDisappear {
            viewModel.applicationDidBecomeInactive()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, _ in
            Task {
                await updateApplicationActivity()
            }
            updateIdleTimerState()
        }
        .onChange(of: viewModel.isRunning) { _, isRunning in
            if isRunning {
                startFeedbackTrigger += 1
            }
        }
    }

    private var alarmIssueIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.alarmIssue != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissAlarmIssue()
                }
            }
        )
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
    }

    private func updateApplicationActivity() async {
        if scenePhase == .active {
            await viewModel.applicationDidBecomeActive()
        } else {
            viewModel.applicationDidBecomeInactive()
        }
    }

    private func startTimer() async {
        await viewModel.start()
    }

    private func startRepeatingTimer() async {
        await viewModel.enableRepeatAndStart()
    }

    private func handleIncomingURL(_ url: URL) {
        Task {
            await applyIncomingURL(url)
        }
    }

    private func applyIncomingURL(_ url: URL) async {
        do {
            let request = try TimerLinkParser.parse(url)

            switch await viewModel.applyTimerLink(request) {
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
