package com.aurascanner.app

import android.net.Uri
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (не FlutterActivity) требуется плагином local_auth
// для показа системного биометрического диалога на Android.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aurascanner.app/native_bridge"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyContentUrisToCache" -> {
                    val rawUris = call.argument<List<String>>("uris").orEmpty()
                    try {
                        result.success(copyContentUrisToCache(rawUris))
                    } catch (e: Exception) {
                        result.error("COPY_URI_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun copyContentUrisToCache(uris: List<String>): List<String> {
        val targetDir = File(cacheDir, "scanner_imports").apply { mkdirs() }
        val resolver = applicationContext.contentResolver

        return uris.mapNotNull { raw ->
            when {
                raw.startsWith("/") -> raw
                raw.startsWith("file://") -> Uri.parse(raw).path
                raw.startsWith("content://") -> {
                    val uri = Uri.parse(raw)
                    val mimeType = resolver.getType(uri)
                    val extension = MimeTypeMap.getSingleton()
                        .getExtensionFromMimeType(mimeType)
                        ?.takeIf { it.isNotBlank() }
                        ?: "jpg"
                    val output = File(
                        targetDir,
                        "scan_${System.currentTimeMillis()}_${raw.hashCode()}.$extension"
                    )
                    resolver.openInputStream(uri)?.use { input ->
                        output.outputStream().use { outputStream ->
                            input.copyTo(outputStream)
                        }
                    }
                    output.absolutePath
                }

                else -> null
            }
        }
    }
}
