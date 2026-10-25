import Foundation
import UIKit

/// Drag-to-dismiss on iOS, done the only way iOS allows: by UIKit itself.
///
/// An iOS app never moves the keyboard. UIKit does, and only for a
/// `UIScrollView` whose `keyboardDismissMode` is `.interactive` — which is all
/// SwiftUI's `.scrollDismissesKeyboard(.interactively)` is, and what RNKC
/// relies on. A Flutter list is not a `UIScrollView`, so this gives UIKit one:
/// an invisible scroll view whose pan recognizer is moved onto the Flutter
/// view, so that every drag on the Flutter view also drives it. When the drag
/// reaches the keyboard, UIKit moves the keyboard with the finger, and
/// [KeyboardMovementObserver] — watching the keyboard view, as RNKC does —
/// reports each frame to Dart as an interactive one.
///
/// Touches are never taken from Flutter: the scroll view is not hit-tested,
/// and its recognizer neither cancels nor delays the touches Flutter sees.
final class InteractiveKeyboardDismiss {
  private var scrollView: DismissScrollView?
  private weak var host: UIView?

  /// Bounds in points a drag must start inside; `nil` accepts the whole view.
  var area: CGRect? {
    didSet { scrollView?.area = area }
  }

  func install() {
    guard scrollView == nil,
          let host = UIApplication.shared.activeWindow?.rootViewController?.view
    else { return }

    let scrollView = DismissScrollView(frame: host.bounds)
    scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scrollView.keyboardDismissMode = .interactive
    // Content no larger than the view, so the drag only ever bounces — the
    // scroll view has nothing to scroll, it exists for UIKit to watch.
    scrollView.alwaysBounceVertical = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.backgroundColor = .clear
    // Status-bar tap-to-top only works while exactly one scroll view opts in,
    // and Flutter's own hidden scroll view already does.
    scrollView.scrollsToTop = false
    scrollView.area = area
    host.insertSubview(scrollView, at: 0)

    let pan = scrollView.panGestureRecognizer
    pan.cancelsTouchesInView = false
    pan.delaysTouchesBegan = false
    pan.delaysTouchesEnded = false
    // A recognizer belongs to one view at a time: this moves it onto the
    // Flutter view, while its target stays the scroll view.
    host.addGestureRecognizer(pan)

    self.scrollView = scrollView
    self.host = host
  }

  func uninstall() {
    guard let scrollView = scrollView else { return }
    host?.removeGestureRecognizer(scrollView.panGestureRecognizer)
    scrollView.removeFromSuperview()
    self.scrollView = nil
    host = nil
  }
}

private final class DismissScrollView: UIScrollView {
  var area: CGRect?

  /// Never the target of a touch: every touch belongs to Flutter.
  override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
    false
  }

  override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
    if recognizer === panGestureRecognizer,
       let area = area,
       let view = recognizer.view,
       !area.contains(recognizer.location(in: view))
    {
      return false
    }
    return super.gestureRecognizerShouldBegin(recognizer)
  }

  /// Alongside, never instead of, anything else on the Flutter view.
  @objc func gestureRecognizer(
    _: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    true
  }
}
