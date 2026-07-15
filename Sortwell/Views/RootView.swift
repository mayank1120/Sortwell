import SwiftUI

struct RootView: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            SortwellToolbar()
            DividerLine()

            Group {
                switch store.route {
                case .welcome:
                    WelcomeView()
                case .scan:
                    ScanView()
                case .summary:
                    ScanSummaryView()
                case .review:
                    ReviewWorkspaceView()
                case .applying:
                    ApplyingView()
                case .results:
                    ResultsView()
                case .activity:
                    ActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SortwellPalette.canvas)
        .foregroundStyle(SortwellPalette.primaryText)
        .sheet(
            isPresented: Binding(
                get: { store.showConfirmation },
                set: { store.showConfirmation = $0 }
            )
        ) {
            ConfirmationView()
                .environment(store)
        }
        .sheet(
            isPresented: Binding(
                get: { store.showActivityDetail },
                set: { store.showActivityDetail = $0 }
            )
        ) {
            ActivityDetailView(journal: store.activityDetailJournal)
                .environment(store)
        }
        .alert(
            "Sortwell",
            isPresented: Binding(
                get: { store.showNoticeAlert },
                set: { store.showNoticeAlert = $0 }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.noticeMessage)
        }
        .task {
            await store.performRecoveryMaintenance()
        }
    }
}

private struct SortwellToolbar: View {
    @Environment(PrototypeStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: SortwellSpacing.md) {
            Button {
                store.route = .welcome
            } label: {
                HStack(spacing: 9) {
                    SortwellIconMark(size: 29)
                    Text("Sortwell")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SortwellPalette.primaryText)
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isOperationActive)
            .opacity(store.isOperationActive ? 0.55 : 1)
            .accessibilityLabel("Return to Sortwell welcome screen")

            Spacer()

            if store.route != .welcome && store.route != .activity {
                WorkflowStageIndicator()
            }

            Spacer()

            StatusPill(title: "Local only", icon: "laptopcomputer.and.arrow.down")

            Button {
                store.route = .activity
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(store.isOperationActive)
            .opacity(store.isOperationActive ? 0.55 : 1)
            .help("Activity and Undo")
            .accessibilityLabel("Open Activity and Undo")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(store.isOperationActive)
            .opacity(store.isOperationActive ? 0.55 : 1)
            .help("Settings")
            .accessibilityLabel("Open Sortwell settings")
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(SortwellPalette.surface)
    }
}

private struct WorkflowStageIndicator: View {
    @Environment(PrototypeStore.self) private var store

    private let stages = ["Scan", "Review", "Apply"]

    private var activeIndex: Int {
        switch store.route {
        case .scan, .summary: 0
        case .review: 1
        case .applying, .results: 2
        default: 0
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SortwellPalette.secondaryText.opacity(0.65))
                }

                HStack(spacing: 5) {
                    if index < activeIndex {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(stage)
                }
                .font(.system(size: 12, weight: index == activeIndex ? .semibold : .regular))
                .foregroundStyle(index <= activeIndex ? SortwellPalette.sage : SortwellPalette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workflow stage: \(stages[activeIndex])")
    }
}

struct ScreenHeading: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(SortwellPalette.sage)
            }
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(SortwellPalette.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(SortwellPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LedgerMetric: View {
    let value: String
    let label: String
    var tint: Color = SortwellPalette.primaryText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 92, alignment: .trailing)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(SortwellPalette.secondaryText)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}
