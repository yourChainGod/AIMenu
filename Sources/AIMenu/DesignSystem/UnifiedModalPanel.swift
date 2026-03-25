import SwiftUI

struct UnifiedModalPanel<Content: View>: View {
    let accent: Color
    let onClose: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        accent: Color,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(OpacityScale.opaque))

                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(OpacityScale.ghost),
                                accent.opacity(OpacityScale.ghost),
                                accent.opacity(0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(OpacityScale.subtle),
                                    Color.white.opacity(OpacityScale.ghost),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 88)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(OpacityScale.subtle),
                                accent.opacity(OpacityScale.subtle),
                                Color.black.opacity(OpacityScale.ghost)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous))
        .shadow(color: accent.opacity(OpacityScale.ghost), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(OpacityScale.muted), radius: 24, x: 0, y: 14)
    }
}

struct ModalOverlay<ModalContent: View>: View {
    let accent: Color
    let onDismiss: () -> Void
    @ViewBuilder let modalContent: ModalContent

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(OpacityScale.overlay)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                UnifiedModalPanel(accent: accent) {
                    modalContent
                }
                .frame(
                    width: min(max(420, geometry.size.width - 28), 540),
                    height: max(460, geometry.size.height - 28)
                )
                .padding(.horizontal, 14)
                .padding(.top, min(28, max(8, geometry.size.height * 0.04)))
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(
                    .move(edge: .top)
                    .combined(with: .scale(scale: 0.97))
                    .combined(with: .opacity)
                )
            }
            .zIndex(20)
        }
    }
}
