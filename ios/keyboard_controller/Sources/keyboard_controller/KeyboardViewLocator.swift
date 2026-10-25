import Foundation
import UIKit

/// Finds the view the keyboard is actually drawn in.
///
/// UIKit exposes no handle on the keyboard, so this walks the window hierarchy
/// for the private container views, exactly as react-native-keyboard-controller
/// does. Watching that view's presentation layer is what makes per-frame
/// tracking possible at all.
enum KeyboardView {
  private static let windowPrefix = "<UITextEffectsWindow"
  private static let containerPrefixes = ["<UIInputSetContainerView", "<UITrackingWindowView"]
  private static let hostPrefixes = ["<UIInputSetHostView", "<UIKeyboardItemContainerView"]

  static func find() -> UIView? {
    for window in UIApplication.shared.allWindows
      where window.description.hasPrefix(windowPrefix)
    {
      for subview in window.subviews
        where subview.description.hasAnyPrefix(containerPrefixes)
      {
        for hostView in subview.subviews
          where hostView.description.hasAnyPrefix(hostPrefixes) && hostView.frame.height != 0
        {
          return hostView
        }
        break
      }
    }

    return nil
  }

  /// The window the keyboard lives in.
  static func window() -> UIWindow? {
    UIApplication.shared.allWindows.first { $0.description.hasPrefix(windowPrefix) }
  }
}

/// Caches the keyboard view, re-resolving it when the window set changes.
final class KeyboardViewLocator {
  static let shared = KeyboardViewLocator()

  private weak var cached: UIView?
  private var cachedWindowsCount = 0

  func resolve() -> UIView? {
    let count = UIApplication.shared.allWindows.count
    if cached == nil || count != cachedWindowsCount {
      cached = KeyboardView.find()
      cachedWindowsCount = count
    }
    return cached
  }
}
