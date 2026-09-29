package com.sam.contentlibrary.content_library

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes two tiny calls for backup/restore through
 * Android's system file picker (Storage Access Framework). No permissions
 * are needed, and the user chooses where the backup goes (Downloads, Google
 * Drive, SD card, ...) so it survives uninstalling the app.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reelbox/backup")
            .setMethodCallHandler { call, result ->
                if (pendingResult != null) {
                    result.error("busy", "Another file dialog is already open", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "save" -> {
                        pendingResult = result
                        pendingBytes = call.argument<ByteArray>("bytes")
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "backup.json")
                        }
                        startActivityForResult(intent, REQ_SAVE)
                    }
                    "open" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, REQ_OPEN)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) return
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // User cancelled the picker.
            result.success(if (requestCode == REQ_SAVE) false else null)
            return
        }
        try {
            if (requestCode == REQ_SAVE) {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes ?: ByteArray(0)) }
                result.success(true)
            } else {
                val text = contentResolver.openInputStream(uri)?.use { String(it.readBytes(), Charsets.UTF_8) }
                result.success(text)
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    companion object {
        private const val REQ_SAVE = 4101
        private const val REQ_OPEN = 4102
    }
}
