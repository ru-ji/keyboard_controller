package com.keyboardcontroller.keyboard_controller

import android.app.Activity
import android.view.View
import android.view.ViewTreeObserver
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.abs

/**
 * Turns the platform's IME animation into the event stream Dart consumes.
 *
 * Ported from react-native-keyboard-controller's `KeyboardAnimationCallback`,
 * with two deliberate differences:
 *
 *  - The callback is installed with `DISPATCH_MODE_CONTINUE_ON_SUBTREE`, not
 *    RNKC's `DISPATCH_MODE_STOP`. Flutter's own `FlutterView` installs an
 *    animation callback to drive `MediaQuery.viewInsets`; stopping dispatch
 *    here would freeze it, so this observer only watches.
 *  - Keyboard size changes and desynchronised state are detected from a global
 *    layout listener rather than from `onApplyWindowInsets`. androidx's
 *    pre-API-30 animation emulation owns the insets listener on this view, and
 *    installing a second one would replace it.
 *
 * Heights are reported in logical pixels as the raw IME inset, so they line up
 * with `MediaQuery.viewInsets.bottom` rather than disagreeing with it.
 */
internal class KeyboardAnimationObserver(
  private val activity: Activity,
  private val events: KeyboardEvents,
) : WindowInsetsAnimationCompat.Callback(
    WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE,
  ) {
  private val view: View
    get() = activity.window.decorView

  private var persistentKeyboardHeight = 0.0
  private var prevKeyboardHeight = 0.0
  private var isKeyboardVisible = false
  private var isTransitioning = false
  private var isInstalled = false
  private var duration = 0

  private val isKeyboardInteractive: Boolean
    get() = duration == -1

  /**
   * Covers what RNKC handles in `onApplyWindowInsets`: the keyboard changing
   * size while it stays open (text to emoji), and states the lifecycle
   * callbacks never report (a permission dialog, a share sheet, a modal
   * closing the keyboard).
   */
  private val layoutListener =
    ViewTreeObserver.OnGlobalLayoutListener {
      if (isTransitioning || InteractiveKeyboardProvider.isInteractive) {
        return@OnGlobalLayoutListener
      }

      val height = currentKeyboardHeight()
      if (height == prevKeyboardHeight) return@OnGlobalLayoutListener

      val wasVisible = isKeyboardVisible
      val isVisible = isKeyboardVisible()

      if (wasVisible && isVisible && height > 0.0) {
        onKeyboardResized(height)
      } else {
        syncKeyboardPosition(height, isVisible)
      }
    }

  fun install() {
    if (isInstalled) return
    isInstalled = true

    ViewCompat.setWindowInsetsAnimationCallback(view, this)
    view.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)

    persistentKeyboardHeight = currentKeyboardHeight()
    prevKeyboardHeight = persistentKeyboardHeight
    isKeyboardVisible = isKeyboardVisible()
  }

  fun uninstall() {
    if (!isInstalled) return
    isInstalled = false

    ViewCompat.setWindowInsetsAnimationCallback(view, null)
    view.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
  }

  override fun onPrepare(animation: WindowInsetsAnimationCompat) {
    super.onPrepare(animation)
    if (!animation.isKeyboardAnimation) return

    isTransitioning = true
  }

  override fun onStart(
    animation: WindowInsetsAnimationCompat,
    bounds: WindowInsetsAnimationCompat.BoundsCompat,
  ): WindowInsetsAnimationCompat.BoundsCompat {
    if (!animation.isKeyboardAnimation) return bounds

    isKeyboardVisible = isKeyboardVisible()
    duration = animation.durationMillis.toInt()

    val keyboardHeight = currentKeyboardHeight()
    // Not updated on hide: the destination is 0 there, and keeping the last
    // open height is what makes `progress` meaningful on the way out.
    if (isKeyboardVisible) persistentKeyboardHeight = keyboardHeight

    events.notification(
      if (isKeyboardVisible) KeyboardEvents.WILL_SHOW else KeyboardEvents.WILL_HIDE,
      keyboardHeight,
      duration,
      activity.isDarkMode,
    )
    events.transition(
      KeyboardEvents.TRANSITION_START,
      keyboardHeight,
      if (isKeyboardVisible) 1.0 else 0.0,
      duration,
    )

    return super.onStart(animation, bounds)
  }

  override fun onProgress(
    insets: WindowInsetsCompat,
    runningAnimations: List<WindowInsetsAnimationCompat>,
  ): WindowInsetsCompat {
    if (runningAnimations.none { it.isKeyboardAnimation }) return insets
    if (!isTransitioning) return insets

    val height = imeInsetOf(insets)
    val progress =
      if (persistentKeyboardHeight == 0.0) {
        0.0
      } else {
        abs(height / persistentKeyboardHeight).let {
          if (it.isNaN() || it.isInfinite()) 0.0 else it
        }
      }

    val interactive = InteractiveKeyboardProvider.isInteractive
    events.transition(
      if (interactive) KeyboardEvents.TRANSITION_INTERACTIVE else KeyboardEvents.TRANSITION_MOVE,
      height,
      progress,
      if (interactive) -1 else duration,
    )

    return insets
  }

  override fun onEnd(animation: WindowInsetsAnimationCompat) {
    super.onEnd(animation)
    if (!animation.isKeyboardAnimation) return

    isTransitioning = false
    duration = animation.durationMillis.toInt()

    val finish =
      Runnable {
        val keyboardHeight = currentKeyboardHeight()
        isKeyboardVisible = isKeyboardVisible()
        prevKeyboardHeight = keyboardHeight

        events.notification(
          if (isKeyboardVisible) KeyboardEvents.DID_SHOW else KeyboardEvents.DID_HIDE,
          keyboardHeight,
          duration,
          activity.isDarkMode,
        )
        events.transition(
          KeyboardEvents.TRANSITION_END,
          keyboardHeight,
          if (isKeyboardVisible) 1.0 else 0.0,
          duration,
        )

        duration = 0
      }

    if (isKeyboardInteractive) {
      // After an interactive gesture the frame is not readable yet — it would
      // always come back as 0 — so the read waits a frame.
      view.post(finish)
    } else {
      finish.run()
    }
  }

  /** The keyboard changed size without a transition: report it instantly. */
  private fun onKeyboardResized(keyboardHeight: Double) {
    duration = 0
    prevKeyboardHeight = keyboardHeight
    persistentKeyboardHeight = keyboardHeight

    events.notification(
      KeyboardEvents.WILL_SHOW,
      keyboardHeight,
      0,
      activity.isDarkMode,
    )
    listOf(
      KeyboardEvents.TRANSITION_START,
      KeyboardEvents.TRANSITION_MOVE,
      KeyboardEvents.TRANSITION_END,
    ).forEach { events.transition(it, keyboardHeight, 1.0, 0) }
    events.notification(KeyboardEvents.DID_SHOW, keyboardHeight, 0, activity.isDarkMode)
  }

  /** Forces Dart back in step after a state change no callback reported. */
  private fun syncKeyboardPosition(
    height: Double,
    isVisible: Boolean,
  ) {
    isKeyboardVisible = isVisible
    prevKeyboardHeight = height
    isTransitioning = false
    duration = 0
    if (isVisible && height > 0.0) persistentKeyboardHeight = height

    val progress = if (isVisible) 1.0 else 0.0
    events.notification(
      if (isVisible) KeyboardEvents.DID_SHOW else KeyboardEvents.DID_HIDE,
      height,
      0,
      activity.isDarkMode,
    )
    listOf(
      KeyboardEvents.TRANSITION_START,
      KeyboardEvents.TRANSITION_MOVE,
      KeyboardEvents.TRANSITION_END,
    ).forEach { events.transition(it, height, progress, 0) }
  }

  private fun isKeyboardVisible(): Boolean =
    ViewCompat.getRootWindowInsets(view)?.isVisible(WindowInsetsCompat.Type.ime()) ?: false

  private fun currentKeyboardHeight(): Double {
    val insets = ViewCompat.getRootWindowInsets(view) ?: return 0.0
    return imeInsetOf(insets)
  }

  private fun imeInsetOf(insets: WindowInsetsCompat): Double =
    insets
      .getInsets(WindowInsetsCompat.Type.ime())
      .bottom
      .toLogical(activity.resources.displayMetrics)
      .coerceAtLeast(0.0)

  private val WindowInsetsAnimationCompat.isKeyboardAnimation: Boolean
    get() = typeMask and WindowInsetsCompat.Type.ime() != 0
}
