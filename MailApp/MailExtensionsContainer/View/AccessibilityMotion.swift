//
//  AccessibilityMotion.swift
//  RNP
//
//  Helpers for respecting `accessibilityReduceMotion`. SwiftUI's
//  `.animation(_:value:)` doesn't automatically disable itself when the
//  user has Reduce Motion on — we have to gate it ourselves.
//
//  Use:
//    .animation(model.reducedMotion ? nil : .default, value: foo)
//  or the `.rnpAnimation(value:)` helper below.
//

import SwiftUI

extension View {
    /// Applies `.default` animation unless Reduce Motion is on, in which
    /// case the change is instantaneous. Mirrors the system's behavior
    /// for sheet transitions.
    func rnpAnimation<V: Equatable>(value: V) -> some View {
        modifier(RnpMotionAwareAnimation(value: value))
    }
}

private struct RnpMotionAwareAnimation<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .default, value: value)
    }
}
