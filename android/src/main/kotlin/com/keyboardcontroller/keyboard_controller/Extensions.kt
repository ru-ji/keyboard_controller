package com.keyboardcontroller.keyboard_controller

import android.content.Context
import android.content.res.Configuration
import android.util.DisplayMetrics

/** Physical pixels to logical (Flutter) pixels. */
internal fun Int.toLogical(metrics: DisplayMetrics): Double = this / metrics.density.toDouble()

/** Logical (Flutter) pixels to physical pixels. */
internal fun Double.toPhysical(metrics: DisplayMetrics): Int = (this * metrics.density).toInt()

internal val Context.isDarkMode: Boolean
  get() =
    resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
      Configuration.UI_MODE_NIGHT_YES
