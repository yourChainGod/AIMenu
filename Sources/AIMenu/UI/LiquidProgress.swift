import SwiftUI

struct LiquidProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let metrics = LiquidProgressMetrics(
                progress: progress,
                totalWidth: geometry.size.width
            )

            ZStack(alignment: .leading) {
                LiquidProgressTrack()

                if metrics.visibleFillWidth > 0 {
                    LiquidProgressFill(tint: tint)
                        .frame(width: metrics.visibleFillWidth, height: metrics.grooveHeight)
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.horizontalInset)
                        .padding(.vertical, metrics.verticalInset)
                }
            }
        }
        .frame(height: LayoutRules.liquidProgressHeight)
    }
}

struct LiquidProgressRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        let metrics = progressMetrics

        ZStack {
            LiquidProgressRingTrack(metrics: metrics)

            if metrics.trimEnd > 0 {
                LiquidProgressRingFill(
                    progress: metrics.trimEnd,
                    tint: tint,
                    metrics: metrics
                )
            }
        }
    }

    private var progressMetrics: LiquidRingMetrics {
        LiquidRingMetrics(progress: progress, lineWidth: lineWidth)
    }
}

struct LiquidProgressMetrics {
    let progress: Double
    let totalWidth: CGFloat

    private var clampedProgress: Double {
        max(0, min(1, progress))
    }

    var horizontalInset: CGFloat {
        1
    }

    var verticalInset: CGFloat {
        1
    }

    var grooveHeight: CGFloat {
        max(4, LayoutRules.liquidProgressHeight - verticalInset * 2)
    }

    var rawFillWidth: CGFloat {
        let availableWidth = max(0, totalWidth - horizontalInset * 2)
        return availableWidth * clampedProgress
    }

    var minimumVisibleFillWidth: CGFloat {
        grooveHeight
    }

    var visibleFillWidth: CGFloat {
        guard rawFillWidth > 0 else {
            return 0
        }

        return max(rawFillWidth, minimumVisibleFillWidth)
    }
}

struct LiquidRingMetrics {
    let progress: Double
    let lineWidth: CGFloat

    var trimEnd: Double {
        max(0, min(1, progress))
    }

    var isFullCircle: Bool {
        trimEnd >= 0.999
    }

    var rotationDegrees: Double {
        -102
    }

    var trackInset: CGFloat {
        max(0.05, lineWidth * 0.01)
    }

    var trackWidth: CGFloat {
        lineWidth * 1.22
    }

    var grooveCenterInset: CGFloat {
        trackInset + trackWidth * 0.5
    }

    var fillInset: CGFloat {
        grooveCenterInset
    }

    var fillWidth: CGFloat {
        max(6.2, trackWidth * 0.82)
    }

    var highlightWidth: CGFloat {
        max(1.8, fillWidth * 0.38)
    }

    var dotThreshold: Double {
        0.032
    }

    var dotDiameter: CGFloat {
        max(5.8, fillWidth * 1.04)
    }
}

struct LiquidGroovePalette {
    let glassTint: Color
    let coreTop: Color
    let coreMid: Color
    let coreBottom: Color
    let topEdge: Color
    let bottomEdge: Color
    let centerGlow: Color
    let innerEdge: Color
    let ringOuterHighlight: Color
    let ringInnerHighlight: Color
    let ringShadow: Color
    let ringShadowSoft: Color
    let ringCoreGlow: Color

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            glassTint = Color.white.opacity(OpacityScale.muted)
            coreTop = Color.white.opacity(OpacityScale.faint)
            coreMid = Color.black.opacity(OpacityScale.accent)
            coreBottom = Color.white.opacity(OpacityScale.ghost)
            topEdge = Color.white.opacity(OpacityScale.medium)
            bottomEdge = Color.black.opacity(OpacityScale.accent)
            centerGlow = Color.white.opacity(OpacityScale.subtle)
            innerEdge = Color.black.opacity(OpacityScale.accent)
            ringOuterHighlight = Color.white.opacity(OpacityScale.medium)
            ringInnerHighlight = Color.white.opacity(OpacityScale.muted)
            ringShadow = Color.black.opacity(OpacityScale.accent)
            ringShadowSoft = Color.black.opacity(OpacityScale.muted)
            ringCoreGlow = Color.white.opacity(OpacityScale.ghost)
        default:
            glassTint = Color.white.opacity(OpacityScale.subtle)
            coreTop = Color.black.opacity(OpacityScale.medium)
            coreMid = Color.black.opacity(OpacityScale.subtle)
            coreBottom = Color.white.opacity(OpacityScale.subtle)
            topEdge = Color.white.opacity(OpacityScale.accent)
            bottomEdge = Color.black.opacity(OpacityScale.muted)
            centerGlow = Color.white.opacity(OpacityScale.muted)
            innerEdge = Color.black.opacity(OpacityScale.muted)
            ringOuterHighlight = Color.white.opacity(OpacityScale.accent)
            ringInnerHighlight = Color.white.opacity(OpacityScale.medium)
            ringShadow = Color.black.opacity(OpacityScale.muted)
            ringShadowSoft = Color.black.opacity(OpacityScale.subtle)
            ringCoreGlow = Color.white.opacity(OpacityScale.ghost)
        }
    }

    var coreGradient: LinearGradient {
        LinearGradient(
            colors: [coreTop, coreMid, coreBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct LiquidProgressTrack: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = LiquidGroovePalette(colorScheme: colorScheme)

        ZStack {
            Capsule()
                .fill(palette.coreGradient)

            Capsule()
                .fill(palette.coreGradient)
                .padding(1)
        }
        .overlay {
            Capsule()
                .stroke(palette.topEdge, lineWidth: 1)
                .blur(radius: 0.35)
                .mask(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.black, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .overlay {
            Capsule()
                .stroke(palette.bottomEdge, lineWidth: 1)
                .blur(radius: 0.45)
                .mask(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .overlay {
            Capsule()
                .fill(palette.centerGlow)
                .padding(.horizontal, 3)
                .padding(.vertical, 2.5)
                .blur(radius: 2.5)
                .mask(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black, Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .opacity(OpacityScale.solid)
        }
    }
}

struct LiquidProgressFill: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.34), location: 0),
                        .init(color: tint.opacity(OpacityScale.dense), location: 0.18),
                        .init(color: tint.opacity(1), location: 0.46),
                        .init(color: tint.opacity(0.84), location: 0.76),
                        .init(color: tint.opacity(0.58), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.26),
                                tint.opacity(OpacityScale.muted),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, 2.5)
                    .padding(.top, 1)
                    .padding(.bottom, 4)
                    .blur(radius: 0.45)
            }
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(OpacityScale.overlay), location: 0),
                                .init(color: Color.white.opacity(OpacityScale.accent), location: 0.22),
                                .init(color: Color.white.opacity(OpacityScale.subtle), location: 0.52),
                                .init(color: Color.clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, 3)
                    .padding(.top, 1)
                    .padding(.bottom, 4.5)
                    .blur(radius: 0.55)
                    .blendMode(.screen)
            }
            .overlay {
                LiquidProgressSurfaceHighlights(tint: tint)
            }
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(OpacityScale.subtle),
                                Color.black.opacity(OpacityScale.muted)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(1)
                    .opacity(OpacityScale.solid)
            }
            .overlay {
                LiquidProgressBevel(tint: tint)
            }
            .shadow(color: tint.opacity(OpacityScale.medium), radius: 2.4, y: 0.9)
    }
}

private struct LiquidProgressSurfaceHighlights: View {
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let width = geometry.size.width
            let endGlowWidth = max(height * 1.05, min(width * 0.24, height * 1.85))

            ZStack {
                endHighlight
                    .frame(width: endGlowWidth, height: height)
                    .position(x: endGlowWidth * 0.5, y: height * 0.5)

                endHighlight
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: endGlowWidth, height: height)
                    .position(x: width - endGlowWidth * 0.5, y: height * 0.5)

                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.clear, location: 0),
                                .init(color: Color.white.opacity(OpacityScale.muted), location: 0.18),
                                .init(color: Color.white.opacity(OpacityScale.medium), location: 0.5),
                                .init(color: Color.white.opacity(OpacityScale.muted), location: 0.82),
                                .init(color: Color.clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, endGlowWidth * 0.55)
                    .padding(.top, 1)
                    .padding(.bottom, height * 0.42)
                    .frame(width: width, height: height)
                    .blendMode(.screen)
                    .mask(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(OpacityScale.solid), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }

    private var endHighlight: some View {
        ZStack {
            Capsule()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.26), location: 0),
                            .init(color: tint.opacity(0.34), location: 0),
                            .init(color: Color.white.opacity(OpacityScale.muted), location: 0.14),
                            .init(color: tint.opacity(OpacityScale.medium), location: 0.22),
                            .init(color: tint.opacity(OpacityScale.subtle), location: 0.5),
                            .init(color: Color.clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.16, y: 0.3),
                        startRadius: 0,
                        endRadius: 18
                    )
                )
                .blendMode(.screen)

            Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(OpacityScale.medium),
                                tint.opacity(OpacityScale.faint),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                    )
                )
                .padding(.vertical, 1)
                .blendMode(.screen)
        }
        .mask(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.78),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .blur(radius: 0.06)
    }
}

private struct LiquidProgressBevel: View {
    let tint: Color

    var body: some View {
        ZStack {
            Capsule()
                .stroke(tint.opacity(OpacityScale.medium), lineWidth: 1)
                .blur(radius: 0.4)
                .mask(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.black, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            Capsule()
                .stroke(Color.black.opacity(OpacityScale.muted), lineWidth: 1)
                .blur(radius: 0.6)
                .mask(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .padding(0.5)
    }
}

struct LiquidProgressRingTrack: View {
    @Environment(\.colorScheme) private var colorScheme

    let metrics: LiquidRingMetrics

    var body: some View {
        GeometryReader { geometry in
            let palette = LiquidGroovePalette(colorScheme: colorScheme)

            ZStack {
                Circle()
                    .inset(by: metrics.trackInset)
                    .strokeBorder(palette.glassTint, lineWidth: metrics.trackWidth)

                Circle()
                    .inset(by: metrics.trackInset)
                    .strokeBorder(palette.coreGradient, lineWidth: metrics.trackWidth)

                Circle()
                    .inset(by: metrics.trackInset)
                    .strokeBorder(palette.topEdge, lineWidth: 1)
                    .blur(radius: 0.35)
                    .mask {
                        ringMask(
                            LinearGradient(
                                colors: [Color.black, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                Circle()
                    .inset(by: metrics.trackInset)
                    .strokeBorder(palette.bottomEdge, lineWidth: 1)
                    .blur(radius: 0.45)
                    .mask {
                        ringMask(
                            LinearGradient(
                                colors: [Color.clear, Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                Circle()
                    .inset(by: metrics.trackInset)
                    .strokeBorder(palette.centerGlow, lineWidth: max(2.6, metrics.trackWidth * 0.42))
                    .blur(radius: 2.1)
                    .mask {
                        ringMask(
                            LinearGradient(
                                colors: [Color.clear, Color.black, Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    .opacity(OpacityScale.overlay)
            }
        }
    }

    private func ringMask(_ style: some ShapeStyle) -> some View {
        Circle()
            .inset(by: metrics.trackInset)
            .strokeBorder(style, lineWidth: metrics.trackWidth)
    }
}

struct LiquidProgressRingFill: View {
    let progress: Double
    let tint: Color
    let metrics: LiquidRingMetrics

    var body: some View {
        GeometryReader { geometry in
            if progress <= 0 {
                EmptyView()
            } else if progress < metrics.dotThreshold {
                startDot(in: geometry.size)
            } else {
                ringSegment(fillGradient, lineWidth: metrics.fillWidth)
                    .shadow(color: tint.opacity(OpacityScale.medium), radius: 2.8, y: 0.9)
                    .overlay {
                        ringSegment(topHighlightGradient, lineWidth: metrics.highlightWidth)
                            .blur(radius: 0.2)
                    }
                    .overlay {
                        ringSegment(innerLiquidGradient, lineWidth: max(2.2, metrics.fillWidth * 0.72))
                            .blur(radius: 0.22)
                            .blendMode(.screen)
                    }
                    .overlay {
                        ringSegment(bottomShadeGradient, lineWidth: max(1.6, metrics.fillWidth * 0.9))
                            .opacity(OpacityScale.overlay)
                    }
            }
        }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(0.34), location: 0),
                .init(color: tint.opacity(OpacityScale.dense), location: 0.18),
                .init(color: tint.opacity(1), location: 0.46),
                .init(color: tint.opacity(0.84), location: 0.76),
                .init(color: tint.opacity(0.58), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topHighlightGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(OpacityScale.overlay), location: 0),
                .init(color: Color.white.opacity(OpacityScale.accent), location: 0.2),
                .init(color: Color.white.opacity(OpacityScale.subtle), location: 0.52),
                .init(color: Color.clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var innerLiquidGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(OpacityScale.accent), location: 0),
                .init(color: tint.opacity(OpacityScale.muted), location: 0.38),
                .init(color: Color.clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var bottomShadeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(OpacityScale.muted),
                Color.black.opacity(OpacityScale.medium)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func ringSegment(_ gradient: LinearGradient, lineWidth: CGFloat) -> some View {
        if metrics.isFullCircle {
            Circle()
                .inset(by: metrics.fillInset)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
        } else {
            Circle()
                .inset(by: metrics.fillInset)
                .trim(from: 0, to: progress)
                .rotation(.degrees(metrics.rotationDegrees))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
        }
    }

    private func startDot(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let angle = metrics.rotationDegrees * .pi / 180
        let radius = max(
            0,
            min(size.width, size.height) * 0.5 - metrics.grooveCenterInset
        )
        let point = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )

        return Circle()
            .fill(fillGradient)
            .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(OpacityScale.accent),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(0.7)
            }
            .shadow(color: tint.opacity(OpacityScale.medium), radius: 2.6, y: 1)
            .position(point)
    }
}
