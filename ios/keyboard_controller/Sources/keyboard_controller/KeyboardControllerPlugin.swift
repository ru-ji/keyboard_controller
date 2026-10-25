import Flutter
import UIKit

/// iOS half of the `keyboard_controller` plugin.
public class KeyboardControllerPlugin: NSObject, FlutterPlugin {
  private var observer: KeyboardMovementObserver?
  private let dismiss = InteractiveKeyboardDismiss()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = KeyboardControllerPlugin()
    let channel = FlutterMethodChannel(
      name: "keyboard_controller",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)

    let events = KeyboardEvents(messenger: registrar.messenger())
    let observer = KeyboardMovementObserver(events: events)
    observer.mount()
    instance.observer = observer
  }

  /// `30` on iOS 26+, where the keyboard is a floating rounded panel, unless
  /// the app opted into the legacy design.
  private static var keyboardBorderRadius: Double {
    #if canImport(UIKit.UIGlassEffect)
      if #available(iOS 26.0, *) {
        let requiresCompat = Bundle.main
          .object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool ?? false
        return requiresCompat ? 0 : 30
      }
    #endif
    return 0
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "getConstants":
      result(["keyboardBorderRadius": Self.keyboardBorderRadius])

    case "setEnabled":
      if arguments["enabled"] as? Bool ?? true {
        observer?.mount()
      } else {
        observer?.unmount()
      }
      result(nil)

    // Android-only.
    case "setInputMode", "setDefaultMode":
      result(nil)

    case "preload":
      UIResponder.preloadKeyboardIfNeeded()
      result(nil)

    case "setTranslucent":
      KeyboardBackdropController.shared
        .setTranslucent(arguments["translucent"] as? Bool ?? false)
      result(nil)

    case "dismiss":
      dismiss(animated: arguments["animated"] as? Bool ?? true)
      result(nil)

    case "keyboardBackgroundColor":
      result(Self.keyboardBackgroundColor())

    case "isInteractiveSupported":
      result(true)

    // UIKit decides how the keyboard follows the finger, so `interpolator`,
    // `offset` and `showOnSwipeUp` — Android's knobs — have no effect here.
    case "setInteractive":
      let enabled = (arguments["enabled"] as? Bool ?? false)
        && (arguments["enableSwipeToDismiss"] as? Bool ?? true)
      if enabled {
        dismiss.install()
      } else {
        dismiss.uninstall()
      }
      result(enabled)

    case "setInteractiveArea":
      dismiss.area = Self.rect(from: call.arguments as? [String: Any])
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func rect(from arguments: [String: Any]?) -> CGRect? {
    guard let arguments = arguments,
          let left = arguments["left"] as? Double,
          let top = arguments["top"] as? Double,
          let right = arguments["right"] as? Double,
          let bottom = arguments["bottom"] as? Double
    else { return nil }

    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  // MARK: Dismiss

  /// Hides the keyboard with no animation.
  ///
  /// Only reached for `animated: false`; everything else is handled in Dart,
  /// where the focus tree stays consistent. `keepFocus` does not come here at
  /// all — Flutter can hide the keyboard through its own text-input channel
  /// without dropping the caret.
  private func dismiss(animated: Bool) {
    // Annotated: `resignFirstResponder()` returns a Bool, which inference
    // would otherwise bake into the closure's type.
    let work: () -> Void = {
      _ = UIResponder.currentFirstResponder?.resignFirstResponder()
    }

    if animated {
      work()
    } else {
      UIView.performWithoutAnimation(work)
    }
  }

  // MARK: Keyboard colour

  /// Average colour of the keyboard's backdrop, for `KeyboardBackgroundView`.
  ///
  /// UIKit exposes no such colour, so it is read from the private backdrop
  /// view's own background where available and otherwise derived from the
  /// keyboard appearance — the same two-step RNKC's Android skins table does
  /// for its platform.
  private static func keyboardBackgroundColor() -> Int? {
    if let window = KeyboardView.window(),
       let backdrop = findBackdrop(in: window),
       let color = backdrop.backgroundColor,
       color.cgColor.alpha > 0
    {
      return argb(of: color)
    }

    let dark = UIResponder.isKeyboardDark
    // The system keyboard greys, measured on iOS 17+.
    return dark ? 0xFF2C_2C2E : 0xFFD1_D3D9
  }

  private static func findBackdrop(in view: UIView) -> UIView? {
    if NSStringFromClass(type(of: view)).hasSuffix("UIKBBackdropView") { return view }
    for subview in view.subviews {
      if let found = findBackdrop(in: subview) { return found }
    }
    return nil
  }

  private static func argb(of color: UIColor) -> Int {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    return (Int(alpha * 255) << 24)
      | (Int(red * 255) << 16)
      | (Int(green * 255) << 8)
      | Int(blue * 255)
  }
}
