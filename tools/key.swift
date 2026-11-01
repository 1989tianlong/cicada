import CoreGraphics
import Foundation
let d = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!; d.flags = .maskAlternate; d.post(tap: .cghidEventTap)
usleep(1_500_000)
let u = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)!; u.flags = .maskAlternate; u.post(tap: .cghidEventTap)
