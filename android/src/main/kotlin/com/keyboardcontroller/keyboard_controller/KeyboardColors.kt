package com.keyboardcontroller.keyboard_controller

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.annotation.ColorInt

/**
 * Background colour of the keyboard currently installed.
 *
 * A port of react-native-keyboard-controller's `Skins.kt`, including its
 * per-IME, per-API colour table: there is no API that reports the IME's colour,
 * so the colour is looked up by package name, with API-qualified resources
 * picking up the Material You neutral tones where the platform has them.
 */
internal object KeyboardColors {
  private const val MAX_RGB_VALUE = 255

  private object ImePackages {
    const val AOSP = "com.android.inputmethod.latin"
    const val GBOARD = "com.google.android.inputmethod.latin"
    const val SWIFT_KEY = "com.touchtype.swiftkey"
    const val GBOARD_TTS = "com.google.android.googlequicksearchbox"
    const val GOOGLE_TTS = "com.google.android.tts"
    const val YANDEX = "ru.yandex.androidkeyboard"
    const val SAMSUNG = "com.samsung.android.honeyboard"
  }

  private val styles: Map<String, Pair<Int, Int>> =
    mapOf(
      ImePackages.AOSP to (R.style.aosp_light to R.style.aosp_light),
      ImePackages.GBOARD to (R.style.gboard_light to R.style.gboard_dark),
      ImePackages.SWIFT_KEY to (R.style.swiftkey_light to R.style.swiftkey_dark),
      ImePackages.GBOARD_TTS to (R.style.gboard_tts_light to R.style.gboard_tts_dark),
      ImePackages.GOOGLE_TTS to (R.style.gboard_tts_light to R.style.gboard_tts_dark),
      ImePackages.YANDEX to (R.style.yandex_light to R.style.yandex_dark),
      ImePackages.SAMSUNG to (R.style.samsung_light to R.style.samsung_dark),
    )

  @ColorInt
  fun of(context: Context): Int {
    val isDark = context.isDarkMode
    val (light, dark) = styles[context.currentImePackage()]
      ?: (R.style.gboard_light to R.style.gboard_dark)

    // On Android 10 the dark theme does not reach the keyboard.
    val style = if (isDark && Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) dark else light

    val attrs = context.obtainStyledAttributes(style, R.styleable.ColorProperties)
    try {
      val color = attrs.getColor(R.styleable.ColorProperties_color, Color.BLACK)
      val tone = attrs.getInt(R.styleable.ColorProperties_tone, 0)
      return shiftRgbChannels(color, tone)
    } finally {
      attrs.recycle()
    }
  }

  private fun Context.currentImePackage(): String? {
    val id =
      Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        ?: return null
    // The setting holds "package/.ServiceName".
    val packageName = id.substringBefore('/')
    if (packageName.isNotEmpty()) return packageName

    val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
    return imm?.enabledInputMethodList?.firstOrNull()?.packageName
  }

  @ColorInt
  private fun shiftRgbChannels(
    @ColorInt color: Int,
    shift: Int,
  ): Int =
    Color.argb(
      Color.alpha(color),
      (Color.red(color) + shift).coerceIn(0, MAX_RGB_VALUE),
      (Color.green(color) + shift).coerceIn(0, MAX_RGB_VALUE),
      (Color.blue(color) + shift).coerceIn(0, MAX_RGB_VALUE),
    )
}
