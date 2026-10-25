import Flutter
import Foundation

/// Sends keyboard frames and notifications to Dart.
///
/// Frames are encoded as a flat list rather than a map: this channel runs at
/// display refresh rate and a list skips the per-frame key hashing a map pays
/// for. The codes mirror `KeyboardMessage` on the Dart side.
final class KeyboardEvents {
  enum Kind: Int {
    case transitionStart = 0
    case transitionMove = 1
    case transitionEnd = 2
    case transitionInteractive = 3

    case willShow = 10
    case didShow = 11
    case willHide = 12
    case didHide = 13
  }

  private let channel: FlutterBasicMessageChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterBasicMessageChannel(
      name: "keyboard_controller/messages",
      binaryMessenger: messenger,
      codec: FlutterStandardMessageCodec.sharedInstance()
    )
  }

  func transition(_ kind: Kind, height: Double, progress: Double, duration: Int) {
    channel.sendMessage([kind.rawValue, height, progress, duration])
  }

  func notification(_ kind: Kind, height: Double, duration: Int, isDark: Bool) {
    channel.sendMessage([
      kind.rawValue,
      height,
      duration,
      Int(Date().timeIntervalSince1970 * 1000),
      isDark,
    ])
  }
}
