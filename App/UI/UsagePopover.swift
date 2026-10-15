import AppKit
import SwiftUI
import UsageKit

/// 메뉴바 아이콘: 가장 빠듯한 한도를 게이지 + 퍼센트로.
struct UsageMenuLabel: View {
    let store: UsageStore

    var body: some View {
        if let headline = store.headline {
            let percent = headline.window.usedPercent
            HStack(spacing: 3) {
                Image(systemName: Self.symbol(for: percent))
                Text("\(Int(percent.rounded()))%").monospacedDigit()
            }
        } else {
            Image(systemName: "gauge.with.dots.needle.0percent")
        }
    }

    static func symbol(for percent: Double) -> String {
        switch percent {
        case ..<17: "gauge.with.dots.needle.0percent"
        case ..<42: "gauge.with.dots.needle.33percent"
        case ..<58: "gauge.with.dots.needle.50percent"
        case ..<84: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }
}

/// 메뉴바 아이콘을 누르면 열리는 창.
struct UsagePopover: View {
    let store: UsageStore
    @Environment(\.openAppSettings) private var openSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                header(now: context.date)
                if store.visibleProviders.isEmpty {
                    Text("표시할 서비스가 없어요. 설정에서 서비스를 켜거나 각 CLI에 로그인해 주세요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(store.visibleProviders) { id in
                    ProviderCard(id: id, state: store.states[id] ?? ProviderState(), now: context.date)
                }
                Divider()
                footer
            }
            .padding(12)
            .frame(width: 340)
        }
        .task {
            // 열 때 1분 넘게 지났으면 바로 새로 고친다
            if (store.lastRefresh ?? .distantPast).timeIntervalSinceNow < -60 { await store.refresh() }
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("AI 사용량").font(.headline)
                Text(updatedText(now: now)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("지금 새로 고침")
            }
        }
    }

    private func updatedText(now: Date) -> String {
        guard let last = store.lastRefresh else { return "불러오는 중…" }
        let minutes = Int(now.timeIntervalSince(last) / 60)
        return minutes < 1 ? "방금 업데이트" : "\(minutes)분 전 업데이트"
    }

    private var footer: some View {
        HStack {
            Button("설정…") {
                openSettings()
            }
            Spacer()
            Button("종료") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// 서비스 하나의 카드.
struct ProviderCard: View {
    let id: ProviderID
    let state: ProviderState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                if let plan = state.snapshot?.plan {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if state.isLoading { ProgressView().controlSize(.mini) }
            }

            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { WindowRow(window: $0, now: now) }
                ForEach(snapshot.notes, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let issue = state.issue {
                IssueRow(issue: issue, staleSince: state.snapshot?.fetchedAt, now: now)
            } else if state.snapshot == nil {
                Text("불러오는 중…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(state.issue != nil && state.snapshot != nil ? 0.75 : 1)
    }

    private var title: String {
        guard let source = state.snapshot?.source, source != id.displayName, id == .gemini else { return id.displayName }
        return "\(id.displayName) · \(source)"
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.title).font(.callout)
                Spacer(minLength: 4)
                if let reset = UsageFormat.resetText(window.resetsAt, now: now) {
                    Text(reset).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            UsageBar(fraction: window.usedPercent / 100, color: Self.color(for: window.usedPercent))
        }
        .accessibilityElement(children: .combine)
    }

    /// 상태 색상: 정상 초록 / 70% 이상 노랑 / 90% 이상 빨강.
    static func color(for percent: Double) -> Color {
        switch percent {
        case 90...: .red
        case 70...: .yellow
        default: .green
        }
    }
}

/// 상태 색을 그대로 보여주는 막대(시스템 진행 막대는 창이 비활성이면 회색이 된다).
struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .animation(.smooth, value: fraction)
    }
}

struct IssueRow: View {
    let issue: UsageIssue
    let staleSince: Date?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                if let staleSince {
                    Text("위 값은 \(max(Int(now.timeIntervalSince(staleSince) / 60), 1))분 전 기준이에요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var symbol: String {
        switch issue.kind {
        case .needsAction: "exclamationmark.circle.fill"
        case .unsupported, .notConfigured: "info.circle.fill"
        case .network: "wifi.exclamationmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch issue.kind {
        case .needsAction: .orange
        case .unsupported, .notConfigured: .secondary
        case .network, .failed: .yellow
        }
    }
}
