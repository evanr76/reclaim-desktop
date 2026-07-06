import SwiftUI

/// UI-only styling for `Priority`. Kept in the app target (not `ReclaimKit`) so
/// the model layer stays free of SwiftUI.
extension Priority {
    var color: Color {
        switch self {
        case .p1: return .red
        case .p2: return .orange
        case .p3: return .blue
        case .p4: return .secondary
        }
    }
}
