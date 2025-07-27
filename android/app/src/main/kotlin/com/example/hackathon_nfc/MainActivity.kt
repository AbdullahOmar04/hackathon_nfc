//mainactivity.kt
package com.example.hackathon_nfc  // ← use your actual package

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
  private val CHANNEL = "hackathon_nfc/hce"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      CHANNEL
    ).setMethodCallHandler { call, result ->
      if (call.method == "setHcePayload") {
        val payload = call.argument<String>("payload") ?: ""
        val prefs = applicationContext
          .getSharedPreferences("HCE_PREF", Context.MODE_PRIVATE)
        prefs.edit()
          .putString("payload", payload)
          .apply()
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
  }
}
