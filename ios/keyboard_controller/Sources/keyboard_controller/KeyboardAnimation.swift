import Foundation
import QuartzCore
import UIKit

/// Models the keyboard's own animation curve so per-frame heights can be
/// reported *ahead* of where the presentation layer currently is.
///
/// A port of react-native-keyboard-controller's animation classes. Reading the
/// presentation layer alone always lags by a frame or two, which shows up as
/// content trailing the keyboard; solving the curve for the current value and
/// stepping forward by the frame duration removes that lag. This is the piece
/// that makes iOS tracking feel attached rather than chased.
public class KeyboardAnimation {
  weak var animation: CAMediaTiming?

  let fromValue: Double
  let toValue: Double
  let duration: Double
  let speed: Double
  let timestamp: CFTimeInterval

  var lastValue: Double

  init(fromValue: Double, toValue: Double, animation: CAMediaTiming, duration: Double) {
    self.fromValue = fromValue
    self.toValue = toValue
    self.animation = animation
    self.duration = duration
    lastValue = fromValue
    speed = Double(animation.speed)
    timestamp = CACurrentMediaTime()
  }

  /// Offset between the animation's start and when it was observed, used on
  /// the simulator where frame intervals are not constant.
  var diff: Double {
    ((animation?.beginTime ?? timestamp) - timestamp)
      .truncatingRemainder(dividingBy: UIUtils.nextFrame)
  }

  var isIncreasing: Bool { fromValue < toValue }

  var isFinished: Bool { lastValue == toValue }

  func valueAt(time _: Double) -> Double {
    fatalError("valueAt(time:) must be overridden")
  }

  /// Inverse of [valueAt]: at what time does the curve reach [value]?
  ///
  /// Solved by bisection, which is cheap enough per frame and needs no
  /// derivative.
  func timingAt(value: Double) -> Double {
    var lowerBound = 0.0
    var upperBound = 1.0
    let tolerance = 0.00001
    var guess = 0.0
    let increasing = isIncreasing

    while (upperBound - lowerBound) > tolerance {
      guess = (lowerBound + upperBound) / 2
      let current = valueAt(time: guess / speed)

      if (current < value && increasing) || (current > value && !increasing) {
        lowerBound = guess
      } else {
        upperBound = guess
      }
    }

    return guess / speed
  }
}

/// Analytic solution of the keyboard's `CASpringAnimation`.
public final class SpringAnimation: KeyboardAnimation {
  private let zeta: Double // damping ratio
  private let omega0: Double // undamped angular frequency
  private let omega1: Double // exponential decay
  private let isUnderDamped: Bool
  private let aUnder: Double
  private let bUnder: Double
  private let aCritical: Double
  private let bCritical: Double

  init(animation: CASpringAnimation, fromValue: Double, toValue: Double) {
    let stiffness = animation.stiffness
    let damping = animation.damping
    let mass = animation.mass
    let v0 = -animation.initialVelocity
    let x0 = toValue - fromValue

    zeta = damping / (2 * sqrt(stiffness * mass))
    omega0 = sqrt(stiffness / mass)
    omega1 = omega0 * sqrt(1.0 - zeta * zeta)
    isUnderDamped = zeta < 1

    if isUnderDamped {
      aCritical = 0
      bCritical = 0
      aUnder = (v0 + zeta * omega0 * x0) / omega1
      bUnder = x0
    } else {
      aCritical = x0
      bCritical = v0 + omega0 * x0
      aUnder = 0
      bUnder = 0
    }

    super.init(
      fromValue: fromValue,
      toValue: toValue,
      animation: animation,
      duration: animation.settlingDuration
    )
  }

  override func valueAt(time: Double) -> Double {
    let t = time * speed

    if isUnderDamped {
      let envelope = exp(-zeta * omega0 * t)
      let angle = omega1 * t
      return toValue - envelope * (aUnder * sin(angle) + bUnder * cos(angle))
    }

    let envelope = exp(-omega0 * t)
    return toValue - envelope * (aCritical + bCritical * t)
  }
}

/// Bézier-timed keyboard animation, for the `CABasicAnimation` case.
public final class TimingAnimation: KeyboardAnimation {
  private let p1: CGPoint
  private let p2: CGPoint

  init(animation: CABasicAnimation, fromValue: Double, toValue: Double) {
    var controlPoints: ContiguousArray<Float> = ContiguousArray([0, 0, 0, 0])
    animation.timingFunction?.getControlPoint(at: 1, values: &controlPoints[0])
    animation.timingFunction?.getControlPoint(at: 2, values: &controlPoints[2])

    p1 = CGPoint(x: CGFloat(controlPoints[0]), y: CGFloat(controlPoints[1]))
    p2 = CGPoint(x: CGFloat(controlPoints[2]), y: CGFloat(controlPoints[3]))

    super.init(
      fromValue: fromValue,
      toValue: toValue,
      animation: animation,
      duration: animation.duration
    )
  }

  override func valueAt(time: Double) -> Double {
    let duration = animation?.duration ?? 0.0
    guard duration > 0 else { return toValue }

    let fraction = min(time / duration, 1.0)
    let progress = bezierY(t: findT(target: fraction, onX: true))

    return fromValue + (toValue - fromValue) * progress
  }

  override func timingAt(value: Double) -> Double {
    guard (toValue - fromValue) != 0 else { return 0 }

    let targetY = ((value - fromValue) / (toValue - fromValue)).clamped(to: 0 ... 1)
    let x = bezierX(t: findT(target: targetY, onX: false))

    return x * (animation?.duration ?? 0.0) / speed
  }

  // The curve runs P0(0,0) → P1 → P2 → P3(1,1), so the first and last terms
  // of the cubic collapse away.
  private func bezier(t: CGFloat, _ valueFor: (CGPoint) -> CGFloat) -> CGFloat {
    let u = 1 - t
    return 3 * u * u * t * valueFor(p1) + 3 * u * t * t * valueFor(p2) + t * t * t
  }

  private func bezierDerivative(t: CGFloat, _ valueFor: (CGPoint) -> CGFloat) -> CGFloat {
    let u = 1 - t
    return (3 * u * u - 6 * t * u) * valueFor(p1)
      + (6 * t * u - 3 * t * t) * valueFor(p2)
      + 3 * t * t
  }

  private func bezierX(t: CGFloat) -> CGFloat { bezier(t: t) { $0.x } }
  private func bezierY(t: CGFloat) -> CGFloat { bezier(t: t) { $0.y } }

  /// Newton-Raphson, converging in a handful of steps for keyboard curves.
  private func findT(target: CGFloat, onX: Bool) -> CGFloat {
    var t: CGFloat = 0.5

    for _ in 0 ..< 100 {
      let value = onX ? bezierX(t: t) : bezierY(t: t)
      let derivative = onX
        ? bezierDerivative(t: t) { $0.x }
        : bezierDerivative(t: t) { $0.y }
      let error = value - target

      if abs(error) < 0.0001 { break }
      if derivative == 0 { break }

      t = (t - error / derivative).clamped(to: 0 ... 1)
    }

    return t
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
