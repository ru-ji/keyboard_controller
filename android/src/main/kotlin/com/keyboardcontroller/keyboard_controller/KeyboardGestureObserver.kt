package com.keyboardcontroller.keyboard_controller

import android.app.Activity
import android.graphics.Rect
import android.os.Build
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.view.Window
import android.view.WindowInsets
import androidx.annotation.RequiresApi
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

/**
 * How finger movement maps onto keyboard position.
 *
 * @param dy distance the finger moved since the previous event.
 * @param fingerFromBottom distance from the finger to the bottom of the window.
 * @param keyboardHeight current keyboard height.
 * @param offset extra slack above the keyboard that still activates the gesture.
 * @return how far the keyboard should move from its current position.
 */
internal fun interface KeyboardInterpolator {
  fun interpolate(
    dy: Int,
    fingerFromBottom: Int,
    keyboardHeight: Int,
    offset: Int,
  ): Int
}

/** The keyboard follows the finger only while the finger is over it. */
internal val IosInterpolator = KeyboardInterpolator { dy, fingerFromBottom, keyboardHeight, offset ->
  if (fingerFromBottom <= keyboardHeight + offset || dy <= 0) dy else 0
}

/** The keyboard follows the finger one-to-one from anywhere. */
internal val LinearKeyboardInterpolator = KeyboardInterpolator { dy, _, _, _ -> dy }

/**
 * Watches touches on the whole window and drags the IME away when the finger
 * reaches it — the behaviour of react-native-keyboard-controller's
 * `KeyboardGestureArea`, and of iOS's interactive dismiss.
 *
 * Two properties matter and both are deliberate:
 *  - **Non-consuming.** Events are observed on their way through the window and
 *    always forwarded, so Flutter's own scrolling and taps are untouched. RNKC
 *    can override `dispatchTouchEvent` on its own view; Flutter has a single
 *    view for the whole app, so the window callback is the equivalent hook.
 *  - **Region-gated.** With [IosInterpolator] the keyboard only follows the
 *    finger once the finger is within the keyboard's own area; above it,
 *    dragging scrolls the list as usual.
 */
@RequiresApi(Build.VERSION_CODES.R)
internal class KeyboardGestureObserver(private val activity: Activity) {
  private val controller = KeyboardAnimationController()

  private var isHandling = false
  private var isInArea = true
  private var lastRawX = 0f
  private var lastRawY = 0f
  private var keyboardHeight = 0
  private var velocityTracker: VelocityTracker? = null
  private var originalCallback: Window.Callback? = null

  /** Extra slack above the keyboard that still counts as "on the keyboard". */
  var offsetPx = 0

  var interpolator: KeyboardInterpolator = IosInterpolator

  /** Whether swiping up may summon a hidden keyboard. */
  var showOnSwipeUp = false

  /** Whether swiping down may dismiss a visible keyboard. */
  var enableSwipeToDismiss = true

  /**
   * Bounds, in physical pixels, that a gesture must start inside; `null`
   * accepts the whole window. Set from the `KeyboardGestureArea` widget's
   * measured rect, since native code only sees raw window touches.
   */
  var area: Rect? = null

  fun install() {
    if (originalCallback != null) return
    val window = activity.window ?: return
    val original = window.callback ?: return
    originalCallback = original
    window.callback = TouchObservingCallback(original, ::onTouch)
  }

  fun uninstall() {
    controller.cancel()
    val original = originalCallback ?: return
    activity.window?.callback = original
    originalCallback = null
    recycleTracker()
  }

  private fun onTouch(event: MotionEvent) {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> onDown(event)
      MotionEvent.ACTION_MOVE -> onMove(event)
      MotionEvent.ACTION_UP -> onUp(event)
      MotionEvent.ACTION_CANCEL -> onCancel()
    }
  }

  private fun onDown(event: MotionEvent) {
    recycleTracker()
    velocityTracker = VelocityTracker.obtain()
    velocityTracker?.addMovement(event)
    lastRawX = event.rawX
    lastRawY = event.rawY
    isHandling = false
    keyboardHeight = 0
    isInArea = area?.contains(event.rawX.roundToInt(), event.rawY.roundToInt()) ?: true
  }

  private fun onMove(event: MotionEvent) {
    if (!isInArea) return

    velocityTracker?.addMovement(event)

    // Screen coordinates, so a resizing window can not skew the deltas.
    val dx = event.rawX - lastRawX
    val dy = event.rawY - lastRawY

    if (!isHandling) {
      // Start handling only once the gesture is mostly vertical and has
      // travelled past the touch slop, so a horizontal swipe is left alone.
      val slop = ViewConfiguration.get(activity).scaledTouchSlop
      isHandling = dy.absoluteValue > dx.absoluteValue && dy.absoluteValue >= slop
      if (!isHandling) return
    }

    val fingerFromBottom = (windowHeight() - event.rawY).roundToInt()

    if (controller.isInsetAnimationInProgress()) {
      if (keyboardHeight == 0) keyboardHeight = controller.getCurrentKeyboardHeight()

      val moveBy =
        interpolator.interpolate(
          dy.roundToInt(),
          fingerFromBottom,
          controller.getCurrentKeyboardHeight(),
          offsetPx,
        )
      if (moveBy != 0) controller.insetBy(moveBy)
    } else if (!controller.isInsetAnimationRequestPending()) {
      val moveBy =
        interpolator.interpolate(
          dy.roundToInt(),
          fingerFromBottom,
          imeInsetBottom(),
          offsetPx,
        )
      if (moveBy != 0 && shouldStartRequest(dy, isImeVisible())) {
        activity.window?.let { controller.startControlRequest(it, it.decorView) }
      }
    }

    lastRawX = event.rawX
    lastRawY = event.rawY
  }

  private fun onUp(event: MotionEvent) {
    velocityTracker?.addMovement(event)
    velocityTracker?.computeCurrentVelocity(VELOCITY_UNITS)

    val velocityY = velocityTracker?.yVelocity
    // Only pass a velocity on if the keyboard actually moved: a tap that
    // happened to register some velocity must not fling it.
    val keyboardMoved =
      !controller.isInsetAnimationInProgress() ||
        keyboardHeight != controller.getCurrentKeyboardHeight()

    if (controller.isInsetAnimationInProgress() || controller.isInsetAnimationRequestPending()) {
      controller.animateToFinish(if (isHandling && keyboardMoved) velocityY else null)
    }

    reset()
  }

  private fun onCancel() {
    controller.cancel()
    reset()
  }

  /** Mirrors RNKC's `shouldStartRequest`. */
  private fun shouldStartRequest(
    dy: Float,
    imeVisible: Boolean,
  ) = when {
    dy < 0 -> !imeVisible && showOnSwipeUp
    dy > 0 -> imeVisible && enableSwipeToDismiss
    else -> false
  }

  private fun reset() {
    isHandling = false
    isInArea = true
    lastRawX = 0f
    lastRawY = 0f
    keyboardHeight = 0
    recycleTracker()
  }

  private fun imeInsetBottom(): Int =
    activity.window?.decorView?.rootWindowInsets
      ?.getInsets(WindowInsets.Type.ime())?.bottom ?: 0

  private fun isImeVisible(): Boolean =
    activity.window?.decorView?.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true

  private fun windowHeight(): Int =
    activity.windowManager?.currentWindowMetrics?.bounds?.height() ?: 0

  private fun recycleTracker() {
    velocityTracker?.recycle()
    velocityTracker = null
  }

  /** Observes touches on their way through the window without consuming them. */
  private class TouchObservingCallback(
    private val delegate: Window.Callback,
    private val onTouch: (MotionEvent) -> Unit,
  ) : Window.Callback by delegate {
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
      onTouch(event)
      return delegate.dispatchTouchEvent(event)
    }
  }

  private companion object {
    /** Velocity measured over 500ms, as RNKC does. */
    const val VELOCITY_UNITS = 500
  }
}
