//
//  HapticManager.swift
//  depth-estimation-demo
//
//  Created by Dohyeop Lim on 2025-07-17.
//

import Foundation
import CoreHaptics
import QuartzCore

class HapticManager {
    private var engine: CHHapticEngine?
    private var lastTapTime: TimeInterval = 0 // 마지막 햅틱 발생 시간, 중복 방지...
    
    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
        } catch { }
    }
    
    func updateHaptic(dangerLevel: Double) {
        guard let engine = engine else { return }
        let now = CACurrentMediaTime()
        let maxInterval: TimeInterval = 1.0
        let minInterval: TimeInterval = 0.15
        let interval = maxInterval - (maxInterval - minInterval) * dangerLevel
        guard now - lastTapTime >= interval, dangerLevel > 0 else { return }
        lastTapTime = now
        
        let intensity = Float(0.3 + 0.7 * dangerLevel)
        let sharpness = Float(0.5)
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
    
    func stopHaptics() {
        lastTapTime = 0
        engine?.stop(completionHandler: nil)
    }
}
