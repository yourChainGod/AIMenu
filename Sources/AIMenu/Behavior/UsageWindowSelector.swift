import Foundation

enum UsageWindowSelector {
    static func pickNearestWindow(_ windows: [UsageWindowRaw], targetSeconds: Int64) -> UsageWindowRaw? {
        windows.min { lhs, rhs in
            let lhsDistance = abs(lhs.limitWindowSeconds - targetSeconds)
            let rhsDistance = abs(rhs.limitWindowSeconds - targetSeconds)
            if lhsDistance == rhsDistance {
                // Prefer the shorter window when both candidates are equally close.
                return lhs.limitWindowSeconds < rhs.limitWindowSeconds
            }
            return lhsDistance < rhsDistance
        }
    }
}
