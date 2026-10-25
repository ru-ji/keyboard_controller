package com.keyboardcontroller.keyboard_controller

import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.Window
import android.view.animation.LinearInterpolator
import androidx.annotation.RequiresApi
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationControlListenerCompat
import androidx.core.view.WindowInsetsAnimationControllerCompat
import androidx.core.view.WindowInsetsCompat
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.roundToInt

/**
 * Owns the IME inset while a gesture drives it.
 *
 * A direct port of react-native-keyboard-controller's
 * `KeyboardAnimationController`. Because this drives the *real* IME inset,
 * Flutter's engine picks the movement up through its own
 * `WindowInsetsAnimation` callback, so `MediaQuery.viewInsets` follows the
 * finger with no Dart-side plumbing.
 */
@RequiresApi(Build.VERSION_CODES.R)
internal class KeyboardAnimationController {
  private var insetsAnimationController: WindowInsetsAnimationControllerCompat? = null
  private var pendingRequestCancellationSignal: CancellationSignal? = null
  private var pendingRequestOnReady: ((WindowInsetsAnimationControllerCompat) -> Unit)? = null

  /** Whether the IME was shown when the current gesture began. */
  private var isImeShownAtStart = false

  private var currentSpringAnimation: SpringAnimation? = null

  private val animationControlListener by lazy {
    object : WindowInsetsAnimationControlListenerCompat {
      override fun onReady(
        controller: WindowInsetsAnimationControllerCompat,
        types: Int,
      ) = onRequestReady(controller)

      override fun onFinished(controller: WindowInsetsAnimationControllerCompat) = reset()

      override fun onCancelled(controller: WindowInsetsAnimationControllerCompat?) = reset()
    }
  }

  fun isInsetAnimationInProgress(): Boolean = insetsAnimationController != null

  fun isInsetAnimationRequestPending(): Boolean = pendingRequestCancellationSignal != null

  /**
   * Asks the window for control over the IME position.
   *
   * @param onRequestReady called once control is granted.
   */
  fun startControlRequest(
    window: Window,
    view: View,
    onRequestReady: ((WindowInsetsAnimationControllerCompat) -> Unit)? = null,
  ) {
    if (isInsetAnimationInProgress()) return

    isImeShownAtStart =
      ViewCompat.getRootWindowInsets(view)?.isVisible(WindowInsetsCompat.Type.ime()) == true

    pendingRequestCancellationSignal = CancellationSignal()
    pendingRequestOnReady = onRequestReady

    InteractiveKeyboardProvider.isInteractive = true

    WindowCompat.getInsetsController(window, view).controlWindowInsetsAnimation(
      WindowInsetsCompat.Type.ime(),
      // -1 means "not a finite animation": the touch controls it entirely.
      -1,
      // A linear interpolator is the right choice for a scrolling gesture: the
      // fraction handed to `setInsetsAndAlpha` is passed through unchanged.
      LinearInterpolator(),
      pendingRequestCancellationSignal,
      animationControlListener,
    )
  }

  /** Moves the IME by [dy] pixels of finger travel; positive is downwards. */
  fun insetBy(dy: Int): Int {
    val controller = insetsAnimationController ?: return 0
    InteractiveKeyboardProvider.isInteractive = true
    return insetTo(controller.currentInsets.bottom - dy)
  }

  fun insetTo(inset: Int): Int {
    val controller = insetsAnimationController ?: return 0

    val hiddenBottom = controller.hiddenStateInsets.bottom
    val shownBottom = controller.shownStateInsets.bottom
    val startBottom = if (isImeShownAtStart) shownBottom else hiddenBottom
    val endBottom = if (isImeShownAtStart) hiddenBottom else shownBottom

    val coercedBottom = inset.coerceIn(hiddenBottom, shownBottom)
    val consumedDy = controller.currentInsets.bottom - coercedBottom
    val span = (endBottom - startBottom).toFloat()

    controller.setInsetsAndAlpha(
      Insets.of(0, 0, 0, coercedBottom),
      1f,
      if (span == 0f) 0f else (coercedBottom - startBottom) / span,
    )

    return consumedDy
  }

  fun getCurrentKeyboardHeight(): Int = insetsAnimationController?.currentInsets?.bottom ?: 0

  /** Reverts to the state the gesture started from. */
  fun cancel() {
    insetsAnimationController?.finish(isImeShownAtStart)
    pendingRequestCancellationSignal?.cancel()
    currentSpringAnimation?.cancel()
    reset()
  }

  /**
   * Settles the IME once the finger lifts.
   *
   * A flick decides by direction (upwards means show); otherwise the position
   * decides, snapping back unless it travelled past [SCROLL_THRESHOLD].
   */
  fun animateToFinish(velocityY: Float? = null) {
    val controller = insetsAnimationController
    if (controller == null) {
      pendingRequestCancellationSignal?.cancel()
      return
    }

    InteractiveKeyboardProvider.isInteractive = false

    val current = controller.currentInsets.bottom
    val shown = controller.shownStateInsets.bottom
    val hidden = controller.hiddenStateInsets.bottom

    when {
      velocityY != null && velocityY != 0f ->
        animateImeToVisibility(visible = velocityY < 0, velocityY = velocityY)
      current == shown -> controller.finish(true)
      current == hidden -> controller.finish(false)
      controller.currentFraction >= SCROLL_THRESHOLD ->
        animateImeToVisibility(!isImeShownAtStart)
      else -> animateImeToVisibility(isImeShownAtStart)
    }
  }

  private fun finish() {
    val controller = insetsAnimationController
    if (controller == null) {
      pendingRequestCancellationSignal?.cancel()
      return
    }

    val current = controller.currentInsets.bottom
    when {
      current == controller.shownStateInsets.bottom -> controller.finish(true)
      current == controller.hiddenStateInsets.bottom -> controller.finish(false)
      controller.currentFraction >= SCROLL_THRESHOLD -> controller.finish(!isImeShownAtStart)
      else -> controller.finish(isImeShownAtStart)
    }
  }

  private fun animateImeToVisibility(
    visible: Boolean,
    velocityY: Float? = null,
  ) {
    val controller = insetsAnimationController ?: return

    val target =
      if (visible) {
        controller.shownStateInsets.bottom.toFloat()
      } else {
        controller.hiddenStateInsets.bottom.toFloat()
      }

    currentSpringAnimation =
      SpringAnimation(FloatValueHolder(controller.currentInsets.bottom.toFloat()))
        .apply {
          spring =
            SpringForce(target).apply {
              // No bounce: a keyboard that overshoots reads as a glitch.
              dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
              stiffness = SpringForce.STIFFNESS_MEDIUM
            }
          addUpdateListener { _, value, _ -> insetTo(value.roundToInt()) }
          if (velocityY != null) setStartVelocity(velocityY)
          addEndListener { animation, _, _, _ ->
            if (animation == currentSpringAnimation) currentSpringAnimation = null
            finish()
          }
          start()
        }
  }

  private fun onRequestReady(controller: WindowInsetsAnimationControllerCompat) {
    pendingRequestCancellationSignal = null
    insetsAnimationController = controller

    pendingRequestOnReady?.invoke(controller)
    pendingRequestOnReady = null
  }

  private fun reset() {
    insetsAnimationController = null
    pendingRequestCancellationSignal = null
    isImeShownAtStart = false

    currentSpringAnimation?.cancel()
    currentSpringAnimation = null
    pendingRequestOnReady = null

    // `animateToFinish` clears this before finishing, but gestures that end
    // through `cancel()`/`onFinished`/`onCancelled` never pass through it. A
    // stranded `true` would make the observer treat the keyboard as moving
    // forever, disabling its desynchronised-state recovery.
    InteractiveKeyboardProvider.isInteractive = false
  }

  private companion object {
    /** 15% of the swipe distance decides between settling open or closed. */
    const val SCROLL_THRESHOLD = 0.15f
  }
}
