import Foundation

struct AlertEvaluator {
    private enum State {
        case armed
        case risingTriggered
        case fallingTriggered
    }

    private var state: State = .armed

    mutating func evaluate(
        changePercent: Double,
        lastPrice: Double,
        rule: AlertRule
    ) -> AlertDirection? {
        switch rule {
        case .percentage(let rising, let falling):
            evaluatePercentage(
                changePercent: changePercent,
                risingThreshold: rising,
                fallingThreshold: falling
            )
        case .targetPrice(let rising, let falling):
            evaluateTargetPrice(
                lastPrice: lastPrice,
                risingTarget: rising,
                fallingTarget: falling
            )
        }
    }

    private mutating func evaluatePercentage(
        changePercent: Double,
        risingThreshold: Double,
        fallingThreshold: Double,
        hysteresis: Double = 0.15
    ) -> AlertDirection? {
        if changePercent >= risingThreshold, state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if changePercent <= -fallingThreshold, state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }
        if changePercent < risingThreshold - hysteresis,
           changePercent > -fallingThreshold + hysteresis {
            state = .armed
        }
        return nil
    }

    private mutating func evaluateTargetPrice(
        lastPrice: Double,
        risingTarget: Double?,
        fallingTarget: Double?,
        hysteresisRatio: Double = 0.0015
    ) -> AlertDirection? {
        if let risingTarget,
           lastPrice >= risingTarget,
           state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if let fallingTarget,
           lastPrice <= fallingTarget,
           state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }

        let isBelowRisingRearm = risingTarget.map {
            lastPrice < $0 * (1 - hysteresisRatio)
        } ?? true
        let isAboveFallingRearm = fallingTarget.map {
            lastPrice > $0 * (1 + hysteresisRatio)
        } ?? true
        if isBelowRisingRearm, isAboveFallingRearm {
            state = .armed
        }
        return nil
    }
}
