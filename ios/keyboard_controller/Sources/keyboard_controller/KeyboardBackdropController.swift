import Foundation
import UIKit

/// Makes the keyboard backdrop see-through so content behind it shows up.
///
/// A port of react-native-keyboard-controller's `KeyboardBackdropController`:
/// UIKit has no API for this, so the private backdrop view is found by class
/// name and faded out. Used by `KeyboardEffects`.
final class KeyboardBackdropController: NSObject {
  static let shared = KeyboardBackdropController()

  private var isTranslucent = false

  override private init() {
    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardWillShow),
      name: UIResponder.keyboardWillShowNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func setTranslucent(_ translucent: Bool) {
    isTranslucent = translucent
    apply()
  }

  // The keyboard rebuilds its backdrop every time it is shown, so the change
  // has to be re-applied rather than set once.
  @objc private func keyboardWillShow() {
    guard isTranslucent else { return }
    apply()
  }

  private func apply() {
    guard let window = KeyboardView.window() else { return }
    apply(in: window)
  }

  private func apply(in view: UIView) {
    if NSStringFromClass(type(of: view)).hasSuffix("UIKBBackdropView") {
      view.alpha = isTranslucent ? 0 : 1
      return
    }

    for subview in view.subviews {
      apply(in: subview)
    }
  }
}
