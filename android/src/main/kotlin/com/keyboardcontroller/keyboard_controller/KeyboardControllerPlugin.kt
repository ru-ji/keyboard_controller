package com.keyboardcontroller.keyboard_controller

import android.app.Activity
import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Android half of the `keyboard_controller` plugin. */
class KeyboardControllerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var methods: MethodChannel
  private lateinit var events: KeyboardEvents

  private var activity: Activity? = null
  private var observer: KeyboardAnimationObserver? = null
  private var gestures: KeyboardGestureObserver? = null
  private var defaultSoftInputMode: Int? = null

  // Kept here so it survives a configuration change, which replaces the
  // activity and with it the observers.
  private var trackingEnabled = true

  /** Interactive control needs `WindowInsetsController`, new in API 30. */
  private val isInteractiveSupported: Boolean
    get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

  // Props are kept here so they survive a configuration change, which tears
  // the activity (and with it the observers) down and builds a new one.
  private var interactiveEnabled = false
  private var interactiveOffset = 0.0
  private var interactiveInterpolator = "ios"
  private var interactiveShowOnSwipeUp = false
  private var interactiveSwipeToDismiss = true
  private var interactiveArea: Rect? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods = MethodChannel(binding.binaryMessenger, "keyboard_controller")
    methods.setMethodCallHandler(this)
    events = KeyboardEvents(binding.binaryMessenger)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding.activity)

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    attach(binding.activity)

  override fun onDetachedFromActivityForConfigChanges() = detach()

  override fun onDetachedFromActivity() = detach()

  private fun attach(activity: Activity) {
    this.activity = activity
    defaultSoftInputMode = activity.window?.attributes?.softInputMode

    observer = KeyboardAnimationObserver(activity, events).also {
      if (trackingEnabled) it.install()
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      gestures = KeyboardGestureObserver(activity).also {
        applyInteractiveProps(it)
        if (interactiveEnabled) it.install()
      }
    }
  }

  private fun detach() {
    observer?.uninstall()
    observer = null
    gestures?.uninstall()
    gestures = null
    activity = null
  }

  private fun applyInteractiveProps(observer: KeyboardGestureObserver) {
    val metrics = activity?.resources?.displayMetrics ?: return
    observer.offsetPx = interactiveOffset.toPhysical(metrics)
    observer.interpolator =
      if (interactiveInterpolator == "linear") LinearKeyboardInterpolator else IosInterpolator
    observer.showOnSwipeUp = interactiveShowOnSwipeUp
    observer.enableSwipeToDismiss = interactiveSwipeToDismiss
    observer.area = interactiveArea
  }

  override fun onMethodCall(
    call: MethodCall,
    result: Result,
  ) {
    when (call.method) {
      "getConstants" ->
        // Android keyboards are full-width and square-cornered.
        result.success(mapOf("keyboardBorderRadius" to 0.0))

      "setInputMode" -> {
        val mode = call.argument<Int>("mode")
        if (mode == null) {
          result.error("E_ARG", "mode is required", null)
        } else {
          setSoftInputMode(mode)
          result.success(null)
        }
      }

      "setDefaultMode" -> {
        defaultSoftInputMode?.let(::setSoftInputMode)
        result.success(null)
      }

      "setEnabled" -> {
        trackingEnabled = call.argument<Boolean>("enabled") ?: true
        if (trackingEnabled) observer?.install() else observer?.uninstall()
        result.success(null)
      }

      // iOS-only.
      "preload", "setTranslucent" -> result.success(null)

      // Only reached for `animated: false`; Dart handles the ordinary case
      // through the focus tree.
      "dismiss" -> {
        dismiss(animated = call.argument<Boolean>("animated") ?: true)
        result.success(null)
      }

      "keyboardBackgroundColor" ->
        result.success(activity?.let { KeyboardColors.of(it) })

      "isInteractiveSupported" -> result.success(isInteractiveSupported)

      "setInteractive" -> {
        interactiveEnabled = call.argument<Boolean>("enabled") ?: false
        interactiveOffset = call.argument<Double>("offset") ?: 0.0
        interactiveInterpolator = call.argument<String>("interpolator") ?: "ios"
        interactiveShowOnSwipeUp = call.argument<Boolean>("showOnSwipeUp") ?: false
        interactiveSwipeToDismiss = call.argument<Boolean>("enableSwipeToDismiss") ?: true

        gestures?.let {
          applyInteractiveProps(it)
          if (interactiveEnabled) it.install() else it.uninstall()
        }
        result.success(isInteractiveSupported && interactiveEnabled)
      }

      "setInteractiveArea" -> {
        interactiveArea = call.toRect()
        gestures?.area = interactiveArea
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  private fun MethodCall.toRect(): Rect? {
    val metrics = activity?.resources?.displayMetrics ?: return null
    val left = argument<Double>("left") ?: return null
    val top = argument<Double>("top") ?: return null
    val right = argument<Double>("right") ?: return null
    val bottom = argument<Double>("bottom") ?: return null

    return Rect(
      left.toPhysical(metrics),
      top.toPhysical(metrics),
      right.toPhysical(metrics),
      bottom.toPhysical(metrics),
    )
  }

  private fun setSoftInputMode(mode: Int) {
    val window = activity?.window ?: return
    if (window.attributes.softInputMode != mode) window.setSoftInputMode(mode)
  }

  /**
   * Hides the keyboard without touching Flutter's focus, so `keepFocus: true`
   * leaves the caret where it is. Dart clears the focus itself otherwise.
   */
  private fun dismiss(animated: Boolean) {
    val activity = this.activity ?: return
    val window = activity.window ?: return
    val view = activity.currentFocus ?: window.decorView

    if (!animated && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      // The only way to skip the transition: take control of the inset and
      // finish it straight away.
      KeyboardAnimationController().startControlRequest(window, view) { it.finish(false) }
      return
    }

    val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
    imm?.hideSoftInputFromWindow(view.windowToken, 0)
  }
}
