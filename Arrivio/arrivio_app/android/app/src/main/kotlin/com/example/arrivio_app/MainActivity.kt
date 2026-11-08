package com.example.arrivio_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingShare: String? = null
    private var shareChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureShare(intent)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arrivio/shared_destination").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedText" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_SEND) {
            captureShare(intent)
            shareChannel?.invokeMethod("shareAvailable", null)
        }
    }

    private fun captureShare(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND) {
            pendingShare = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""
        }
    }
}
