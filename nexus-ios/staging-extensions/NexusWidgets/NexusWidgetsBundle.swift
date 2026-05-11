// NexusWidgetsBundle.swift
// Bundle every WidgetKit widget the iOS Widget Extension exposes:
//   - BriefingWidget           — Lock Screen + Home Screen briefing glance
//   - LatestActivityWidget     — last Arena tool call Eve fired
//   - EveLiveActivity          — Dynamic Island streaming reply / ongoing op
//
// Add this file to a new "Widget Extension" target in the Xcode project.
// The target's @main entry is the bundle below.

import WidgetKit
import SwiftUI

@main
struct NexusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BriefingWidget()
        LatestActivityWidget()
        if #available(iOS 16.1, *) {
            EveLiveActivity()
        }
    }
}
