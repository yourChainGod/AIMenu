import SwiftUI

// MARK: - Opacity Scale

enum OpacityScale {
    static let ghost:   Double = 0.02
    static let faint:   Double = 0.04
    static let subtle:  Double = 0.06
    static let muted:   Double = 0.10
    static let medium:  Double = 0.16
    static let accent:  Double = 0.24
    static let overlay: Double = 0.42
    static let solid:   Double = 0.70
    static let dense:   Double = 0.92
    static let opaque:  Double = 0.97
}

// MARK: - Animation Presets

enum AnimationPreset {
    static let snappy: Animation = .easeInOut(duration: 0.12)
    static let hover:  Animation = .easeInOut(duration: 0.15)
    static let quick:  Animation = .easeInOut(duration: 0.18)
    static let sheet:  Animation = .spring(response: 0.28, dampingFraction: 0.84)
    static let expand: Animation = .spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: - Semantic Accent Palette

enum InterfaceAccent {
    static let remote = Color.teal
    static let runtime = Color.indigo
    static let workflow = Color.green
    static let support = Color.mint
    static let caution = Color.orange
}
