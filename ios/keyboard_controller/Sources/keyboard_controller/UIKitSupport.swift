import Foundation
import UIKit

extension UIApplication {
  /// The window the user is actually looking at.
  var activeWindow: UIWindow? {
    for scene in connectedScenes {
      if scene.activationState == .foregroundActive,
         let windowScene = scene as? UIWindowScene,
         let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow })
      {
        return keyWindow
      }
    }
    // A scene can be .foregroundInactive while a keyboard transition runs.
    return connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
      .first
  }

  /// Every window, including the text-effects window the keyboard lives in.
  var allWindows: [UIWindow] {
    connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
  }
}

extension UIView {
  func findFirstResponder() -> UIView? {
    if isFirstResponder { return self }
    for subview in subviews {
      if let responder = subview.findFirstResponder() { return responder }
    }
    return nil
  }
}

extension UIResponder {
  /// The view that currently owns text input.
  ///
  /// On Flutter this is a `FlutterTextInputView`, the hidden view the engine
  /// keeps in sync with whichever Dart `EditableText` has focus. It is what
  /// supplies the keyboard's type and appearance.
  static var currentFirstResponder: UIView? {
    UIApplication.shared.activeWindow?.findFirstResponder()
  }

  private static var hasPreloadedKeyboard = false
  static var isKeyboardPreloading = false

  /// Builds the keyboard UI ahead of time so the first focus has no lag.
  ///
  /// https://stackoverflow.com/a/20436797
  static func preloadKeyboardIfNeeded() {
    guard !hasPreloadedKeyboard else { return }
    hasPreloadedKeyboard = true
    isKeyboardPreloading = true

    DispatchQueue.main.async {
      defer { isKeyboardPreloading = false }
      guard let window = UIApplication.shared.activeWindow else { return }

      let lagFreeField = UITextField(frame: .zero)
      lagFreeField.isHidden = true
      window.addSubview(lagFreeField)
      lagFreeField.becomeFirstResponder()
      lagFreeField.resignFirstResponder()
      lagFreeField.removeFromSuperview()
    }
  }

  /// Whether the keyboard is drawn dark, for the toolbar theme.
  static var isKeyboardDark: Bool {
    guard let responder = currentFirstResponder else {
      return UIScreen.main.traitCollection.userInterfaceStyle == .dark
    }

    // Compared rather than switched: the trait is an optional protocol member,
    // and `==` reads the same whether or not it arrives wrapped.
    if let traits = responder as? UITextInputTraits {
      let appearance = traits.keyboardAppearance
      if appearance == .dark { return true }
      if appearance == .light { return false }
    }

    return responder.traitCollection.userInterfaceStyle == .dark
  }
}

extension Notification {
  /// `(durationMs, endFrame)` from a keyboard notification.
  func keyboardMetaData() -> (Int, NSValue?) {
    let duration = Int(
      (userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0) * 1000
    )
    return (duration, userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)
  }
}

extension Optional where Wrapped == UIView {
  /// `(visibleHeight, frameY)` read from the *presentation* layer, i.e. where
  /// the view is on screen this frame rather than where it will end up.
  var frameTransitionInWindow: (Double, Double) {
    let crossFading = (self?.layer.presentation()?.animationKeys() ?? []).contains("opacity")
    let frameY = self?.layer.presentation()?.frame.origin.y ?? 0
    let windowH = self?.window?.bounds.size.height ?? 0
    var position = windowH - frameY

    // With cross-fade transitions the keyboard changes `opacity` instead of
    // translating, so the visible height has to be scaled by it.
    if crossFading {
      let opacity = self?.layer.presentation()?.opacity ?? 0
      position = CGFloat(opacity) * position
    }

    return (position, frameY)
  }
}

extension String {
  func hasAnyPrefix(_ prefixes: [String]) -> Bool {
    prefixes.contains { hasPrefix($0) }
  }
}

enum UIUtils {
  /// One frame at 60fps, used when approximating animation timing.
  static let nextFrame: Double = 1.0 / 60.0
}
