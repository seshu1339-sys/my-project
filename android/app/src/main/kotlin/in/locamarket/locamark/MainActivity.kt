package `in`.locamarket.locamark

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Photo -> WebP, used by every upload in all three apps (lib/services/image_compress_native.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "in.locamarket/image").setMethodCallHandler { call, result ->
            if (call.method != "compressToWebp") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val maxSide = call.argument<Int>("maxSide") ?: 1600
            val quality = call.argument<Int>("quality") ?: 80
            if (bytes == null) {
                result.error("bad-args", "No image bytes", null)
                return@setMethodCallHandler
            }
            // Off the UI thread: decoding and encoding a big photo takes a moment.
            Thread {
                try {
                    val out = ImageWebp.compress(bytes, maxSide, quality)
                    runOnUiThread { result.success(out) }
                } catch (e: Throwable) {
                    runOnUiThread { result.error("compress-failed", e.message, null) }
                }
            }.start()
        }
    }
}
