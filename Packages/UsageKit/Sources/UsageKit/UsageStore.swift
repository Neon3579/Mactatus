import CoreKit
import Foundation
import Observation

/// 서비스별 사용량을 주기적으로 모아 화면에 내보낸다.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var states: [ProviderID: ProviderState] = [:]
    public private(set) var isRefreshing = false
    public private(set) var lastRefresh: Date?

    /// 새 결과가 들어올 때마다 불린다(알림 등).
    @ObservationIgnored public var onSnapshot: ((UsageSnapshot) -> Void)?

    @ObservationIgnored private let providers: [ProviderID: any UsageProvider]
    @ObservationIgnored private let isEnabled: (ProviderID) -> Bool
    @ObservationIgnored private let interval: () -> TimeInterval
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var consecutiveFailures: [ProviderID: Int] = [:]

    public init(providers: [any UsageProvider], isEnabled: @escaping (ProviderID) -> Bool, interval: @escaping () -> TimeInterval) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.isEnabled = isEnabled
        self.interval = interval
    }

    /// 화면에 보여줄 서비스(켜져 있고, 설치·로그인이 안 된 것은 뺀다). 아직 조회 전이면 보여준다.
    public var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { id in
            guard isEnabled(id) else { return false }
            guard let state = states[id] else { return true }
            return state.snapshot != nil || state.issue?.kind != .notConfigured
        }
    }

    /// 메뉴바 아이콘에 쓸 가장 빠듯한 한도.
    public var headline: (provider: ProviderID, window: UsageWindow)? {
        visibleProviders
            .compactMap { id in states[id]?.snapshot?.mostConstrained.map { (id, $0) } }
            .max { $0.1.usedPercent < $1.1.usedPercent }
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let wait = self?.interval() ?? 180
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }
        let targets = providers.values.filter { provider in
            guard isEnabled(provider.id) else { return false }
            // 네트워크가 아닌 실패가 이어지면 조회 간격을 늘린다(최대 4배)
            let failures = consecutiveFailures[provider.id, default: 0]
            guard failures > 0, let last = states[provider.id]?.lastAttempt else { return true }
            return Date().timeIntervalSince(last) >= interval() * Double(min(1 << failures, 4)) * 0.9
        }
        for provider in targets { states[provider.id, default: ProviderState()].isLoading = true }

        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, UsageIssue>).self) { group in
            for provider in targets {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.fetch()))
                    } catch let issue as UsageIssue {
                        return (provider.id, .failure(issue))
                    } catch {
                        return (provider.id, .failure(.failed(error.localizedDescription)))
                    }
                }
            }
            for await (id, result) in group {
                var state = states[id, default: ProviderState()]
                state.isLoading = false
                state.lastAttempt = Date()
                switch result {
                case .success(let snapshot):
                    state.snapshot = snapshot
                    state.issue = nil
                    consecutiveFailures[id] = 0
                    onSnapshot?(snapshot)
                case .failure(let issue):
                    state.issue = issue
                    if issue.kind != .network { consecutiveFailures[id, default: 0] += 1 }
                    Log.usage.error("\(id.rawValue, privacy: .public) 조회 실패: \(issue.message, privacy: .public)")
                }
                states[id] = state
            }
        }
    }
}
