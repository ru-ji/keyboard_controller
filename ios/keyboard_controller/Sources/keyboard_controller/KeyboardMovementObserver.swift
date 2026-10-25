import Foundation
import QuartzCore
import UIKit

/// Turns UIKit's keyboard notifications into the event stream Dart consumes.
///
/// A port of react-native-keyboard-controller's `KeyboardMovementObserver`.
/// UIKit gives two notifications and no frames in between, so per-frame
/// tracking comes from a `CADisplayLink` reading the keyboard view's
/// presentation layer, corrected by the modelled animation curve (see
/// [KeyboardAnimation]) so the reported height leads rather than lags.
final class KeyboardMovementObserver: NSObject {
  private let events: KeyboardEvents

  private var displayLink: CADisplayLink?
  private var interactiveObserver: NSKeyValueObservation?
  private var isMounted = false

  private var keyboardHeight: CGFloat = 0
  private var prevKeyboardPosition: Double = 0
  private var duration = 0
  private var animation: KeyboardAnimation?

  /// Held so the scheduled `did` event can replay the notification.
  private var notification: Notification?
  private var keyboardDidTask: DispatchWorkItem?

  private var keyboardView: UIView? { KeyboardViewLocator.shared.resolve() }

  init(events: KeyboardEvents) {
    self.events = events
    super.init()

    let link = CADisplayLink(target: self, selector: #selector(updateKeyboardFrame))
    // Falls back to 60fps on devices without a ProMotion display.
    link.preferredFramesPerSecond = 120
    link.add(to: .main, forMode: .common)
    link.isPaused = true
    displayLink = link
  }

  deinit {
    displayLink?.invalidate()
    displayLink = nil
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: Lifecycle

  func mount() {
    guard !isMounted else { return }
    isMounted = true

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillAppear),
      name: UIResponder.keyboardWillShowNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillDisappear),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
  }

  func unmount() {
    isMounted = false
    removeInteractiveObserver()
    displayLink?.isPaused = true
    // swiftlint:disable:next notification_center_detachment
    NotificationCenter.default.removeObserver(self)
  }

  var currentKeyboardHeight: CGFloat { keyboardHeight }

  var isKeyboardVisible: Bool { prevKeyboardPosition > 0 }

  // MARK: Notifications

  @objc private func keyboardWillAppear(_ notification: Notification) {
    guard !UIResponder.isKeyboardPreloading else { return }

    let (duration, frame) = notification.keyboardMetaData()
    guard let frame = frame else { return }

    keyboardHeight = frame.cgRectValue.size.height
    self.notification = notification
    self.duration = duration

    // Foldables can report a `willShow` with a zero height on rotation.
    let progress: Double = keyboardHeight > 0 ? 1 : 0

    events.notification(
      .willShow,
      height: Double(keyboardHeight),
      duration: duration,
      isDark: UIResponder.isKeyboardDark
    )
    events.transition(
      .transitionStart,
      height: Double(keyboardHeight),
      progress: progress,
      duration: duration
    )

    startWatching()
    initializeAnimation(from: prevKeyboardPosition, to: Double(keyboardHeight))
    scheduleDidEvent(
      height: Double(keyboardHeight),
      after: animation?.duration ?? Double(duration) / 1000
    )
  }

  @objc private func keyboardWillDisappear(_ notification: Notification) {
    guard !UIResponder.isKeyboardPreloading else { return }

    let (duration, _) = notification.keyboardMetaData()
    self.duration = duration

    var updated = notification
    // The end frame is replaced with zero: that is where the keyboard will be
    // once the animation finishes, which is what the `did` event must report.
    updated.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] =
      NSValue(cgRect: .zero)
    self.notification = updated

    events.notification(
      .willHide,
      height: 0,
      duration: duration,
      isDark: UIResponder.isKeyboardDark
    )
    events.transition(.transitionStart, height: 0, progress: 0, duration: duration)

    startWatching()
    removeInteractiveObserver()
    initializeAnimation(from: prevKeyboardPosition, to: 0)
    scheduleDidEvent(height: 0, after: animation?.duration ?? Double(duration) / 1000)
  }

  private func keyboardDidAppear() {
    let height = Double(keyboardHeight)

    events.transition(
      .transitionEnd,
      height: height,
      progress: keyboardHeight > 0 ? 1 : 0,
      duration: duration
    )
    events.notification(
      .didShow,
      height: height,
      duration: duration,
      isDark: UIResponder.isKeyboardDark
    )

    stopWatching()
    prevKeyboardPosition = height
    setupInteractiveObserver()
    animation = nil
  }

  private func keyboardDidDisappear() {
    events.transition(.transitionEnd, height: 0, progress: 0, duration: duration)
    events.notification(
      .didHide,
      height: 0,
      duration: duration,
      isDark: UIResponder.isKeyboardDark
    )

    stopWatching()
    prevKeyboardPosition = 0
    animation = nil
  }

  /// UIKit's `keyboardDidShow`/`keyboardDidHide` are not dependable while the
  /// frame is being tracked, so the end of the transition is scheduled from
  /// the animation's own duration instead.
  private func scheduleDidEvent(height: Double, after delay: Double) {
    keyboardDidTask?.cancel()
    guard notification != nil else { return }

    let task = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if height > 0 {
        self.keyboardDidAppear()
      } else {
        self.keyboardDidDisappear()
      }
    }

    keyboardDidTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
  }

  // MARK: Per-frame tracking

  private func startWatching() {
    // `will` notifications can arrive more than once; an already-running link
    // must not be restarted.
    guard displayLink?.isPaused == true else { return }
    displayLink?.isPaused = false
  }

  private func stopWatching() {
    displayLink?.isPaused = true
  }

  @objc private func updateKeyboardFrame(link: CADisplayLink) {
    guard let view = keyboardView else { return }

    let (visibleHeight, frameY) = Optional(view).frameTransitionInWindow
    var keyboardPosition = CGFloat(visibleHeight)

    if Double(keyboardPosition) == prevKeyboardPosition || frameY == 0 { return }

    if animation == nil {
      initializeAnimation(from: prevKeyboardPosition, to: Double(keyboardHeight))
    }

    prevKeyboardPosition = Double(keyboardPosition)

    if let animation = animation {
      if animation.isFinished { return }

      let baseDuration = animation.timingAt(value: Double(keyboardPosition))

      #if targetEnvironment(simulator)
        // Frame intervals are not constant on the simulator, so the offset
        // between the animation's start and the observation is used instead
        // of a fixed step.
        let duration = baseDuration + animation.diff
      #else
        // Two frames: the presentation layer shows the previous frame, and the
        // value being reported is for the next one.
        let duration = baseDuration + link.duration * 2
      #endif

      let predicted = CGFloat(animation.valueAt(time: duration))
      // A spring never exactly reaches its final value, so the prediction is
      // raced against the observed position in the direction of travel.
      let race: (CGFloat, CGFloat) -> CGFloat = animation.isIncreasing ? max : min
      keyboardPosition = race(predicted, keyboardPosition)
      animation.lastValue = Double(keyboardPosition)
    }

    events.transition(
      .transitionMove,
      height: Double(keyboardPosition),
      progress: keyboardHeight == 0 ? 0 : Double(keyboardPosition / keyboardHeight),
      duration: duration
    )
  }

  private func initializeAnimation(from: Double, to: Double) {
    for key in ["position", "opacity"] {
      guard let keyboardAnimation =
        keyboardView?.layer.presentation()?.animation(forKey: key)
      else { continue }

      if let spring = keyboardAnimation as? CASpringAnimation {
        animation = SpringAnimation(animation: spring, fromValue: from, toValue: to)
      } else if let basic = keyboardAnimation as? CABasicAnimation {
        animation = TimingAnimation(animation: basic, fromValue: from, toValue: to)
      }
      return
    }
  }

  // MARK: Interactive movement

  /// Reports a frame of finger-driven movement — UIKit moving the keyboard
  /// for an interactive scroll view, which [InteractiveKeyboardDismiss]
  /// provides on top of Flutter.
  private func emitInteractive(height: CGFloat) {
    keyboardDidTask?.cancel()
    prevKeyboardPosition = Double(height)

    events.transition(
      .transitionInteractive,
      height: Double(height),
      progress: keyboardHeight == 0 ? 0 : Double(height / keyboardHeight),
      duration: -1
    )
  }

  /// Watches the keyboard view's centre, which catches keyboard movement this
  /// plugin did not cause — a native scroll view with
  /// `keyboardDismissMode = .interactive`, for instance.
  private func setupInteractiveObserver() {
    guard interactiveObserver == nil, let view = keyboardView else { return }

    interactiveObserver = view.observe(\.center, options: .new) { [weak self] _, change in
      guard let self = self, let center = change.newValue else { return }
      self.keyboardDidMoveInteractively(center: center)
    }
  }

  private func removeInteractiveObserver() {
    interactiveObserver?.invalidate()
    interactiveObserver = nil
  }

  private func keyboardDidMoveInteractively(center: CGPoint) {
    if UIResponder.isKeyboardPreloading { return }
    // A running system animation already drives the display link.
    if displayLink?.isPaused == false { return }

    guard let view = keyboardView else { return }

    let windowHeight = view.window?.bounds.size.height ?? 0
    let rawPosition = windowHeight - center.y

    // A height that disagrees with the view's bounds means the value is mid
    // re-layout and would cause a jump.
    if floor(view.bounds.size.height) != floor(keyboardHeight) { return }

    // `center` is the middle of the keyboard view, so it travels half as far
    // as the keyboard's top edge.
    let position = interpolate(
      value: rawPosition,
      inputRange: (keyboardHeight / 2, -keyboardHeight / 2),
      outputRange: (keyboardHeight, 0)
    )

    // Zero arrives just before `keyboardWillHide`, which reports it anyway.
    if position == 0 { return }

    emitInteractive(height: position)
  }

  private func interpolate(
    value: CGFloat,
    inputRange: (CGFloat, CGFloat),
    outputRange: (CGFloat, CGFloat)
  ) -> CGFloat {
    let inputMin = min(inputRange.0, inputRange.1)
    let inputMax = max(inputRange.0, inputRange.1)
    let outputMin = min(outputRange.0, outputRange.1)
    let outputMax = max(outputRange.0, outputRange.1)

    guard inputMax != inputMin else { return outputMax }

    let normalized = (value - inputMin) / (inputMax - inputMin)
    return outputMin + (outputMax - outputMin) * normalized
  }
}
