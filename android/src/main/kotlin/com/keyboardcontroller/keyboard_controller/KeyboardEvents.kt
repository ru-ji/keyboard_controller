package com.keyboardcontroller.keyboard_controller

import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Sends keyboard frames and notifications to Dart.
 *
 * Frames are encoded as a flat list rather than a map: this channel runs at
 * display refresh rate and a list skips the per-frame key hashing a map pays
 * for. The codes mirror `KeyboardMessage` on the Dart side.
 */
internal class KeyboardEvents(messenger: BinaryMessenger) {
  private val channel =
    BasicMessageChannel(
      messenger,
      "keyboard_controller/messages",
      StandardMessageCodec.INSTANCE,
    )

  fun transition(
    kind: Int,
    height: Double,
    progress: Double,
    duration: Int,
  ) {
    channel.send(listOf(kind, height, progress, duration))
  }

  fun notification(
    kind: Int,
    height: Double,
    duration: Int,
    isDark: Boolean,
  ) {
    channel.send(listOf(kind, height, duration, System.currentTimeMillis(), isDark))
  }

  companion object {
    const val TRANSITION_START = 0
    const val TRANSITION_MOVE = 1
    const val TRANSITION_END = 2
    const val TRANSITION_INTERACTIVE = 3

    const val WILL_SHOW = 10
    const val DID_SHOW = 11
    const val WILL_HIDE = 12
    const val DID_HIDE = 13
  }
}
