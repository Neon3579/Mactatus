import SwiftUI

/// 노치 창의 내용: 상태에 맞는 크기의 검은 모양과 그 안의 모듈 내용.
struct NotchRootView: View {
    let controller: NotchController

    var body: some View {
        let state = controller.state
        let size = controller.shapeSize
        let shape = NotchShape(topRadius: NotchController.topRadius, bottomRadius: state == .expanded ? 24 : 10)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(.black)
                    .shadow(color: .black.opacity(state == .expanded ? 0.4 : 0), radius: 14, y: 6)
                // 모양이 커지고 작아지는 동안 내용이 검은 모양 밖으로 비치지 않게 잘라 그리고,
                // 미니 ↔ 펼침 내용이 겹쳐 보이지 않게 이전 내용은 바로 지우고 새 내용은 모양이 자란 뒤에 보인다
                content(state)
                    .padding(.horizontal, NotchController.topRadius)
                    .id(state)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.12)),
                        removal: .opacity.animation(.linear(duration: 0.05))))
                    .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: state)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(_ state: NotchController.State) -> some View {
        let notch = controller.geometry?.notch.size ?? .zero
        switch state {
        case .idle:
            Color.clear
        case .compact:
            if let module = controller.compactModule {
                HStack(spacing: 0) {
                    module.compactLeading()
                        .frame(width: module.compactWingWidth, height: notch.height)
                    Color.clear.frame(width: notch.width)
                    module.compactTrailing()
                        .frame(width: module.compactWingWidth, height: notch.height)
                }
            }
        case .expanded:
            VStack(spacing: 0) {
                header(notchWidth: notch.width)
                    .frame(height: notch.height)
                if let module = controller.selectedModule {
                    module.expanded()
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("표시할 내용이 없어요")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// 펼친 화면 맨 윗줄: 노치 왼쪽에 탭, 오른쪽에 설정
    private func header(notchWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(controller.modules.filter(\.showsTab), id: \.id) { module in
                    let selected = module.id == controller.selectedModule?.id
                    Button {
                        controller.select(module)
                    } label: {
                        Image(systemName: module.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 22)
                            .background(selected ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(.clear), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .help(module.title)
                    .accessibilityLabel(module.title)
                }
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            Button {
                controller.collapse()
                controller.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("설정")
            .accessibilityLabel("설정")
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
