package com.keyboardcontroller.keyboard_controller

/**
 * Whether a finger is currently driving the keyboard.
 *
 * Set by [KeyboardAnimationController] and read by [KeyboardAnimationObserver],
 * which uses it to report frames as interactive rather than as part of a
 * system animation.
 */
internal object InteractiveKeyboardProvider {
  var isInteractive = false
}
