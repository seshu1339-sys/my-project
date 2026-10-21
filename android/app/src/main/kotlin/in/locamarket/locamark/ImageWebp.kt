package `in`.locamarket.locamark

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Shrinks a photo so its longest side is at most [maxSide] pixels and re-encodes it as WebP. Phone photos
 * (3-8 MB JPEGs) come out at roughly 100-300 KB. The camera's rotation (EXIF) is applied first, so the
 * picture is never uploaded sideways.
 */
object ImageWebp {
    fun compress(input: ByteArray, maxSide: Int, quality: Int): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(input, 0, input.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Not an image" }

        // Decode at a reduced size when the photo is much bigger than needed (saves memory).
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        var bitmap = requireNotNull(BitmapFactory.decodeByteArray(input, 0, input.size, options)) { "Could not read the image" }

        val rotation = exifRotation(input)
        val longest = max(bitmap.width, bitmap.height)
        val scale = if (longest > maxSide) maxSide.toFloat() / longest else 1f
        if (rotation != 0 || scale < 1f) {
            val matrix = Matrix()
            if (scale < 1f) matrix.postScale(scale, scale)
            if (rotation != 0) matrix.postRotate(rotation.toFloat())
            val changed = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (changed !== bitmap) bitmap.recycle()
            bitmap = changed
        }

        val format = if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else @Suppress("DEPRECATION") Bitmap.CompressFormat.WEBP
        val out = ByteArrayOutputStream()
        bitmap.compress(format, quality.coerceIn(1, 100), out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun exifRotation(input: ByteArray): Int = try {
        val orientation = ExifInterface(ByteArrayInputStream(input)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (e: Exception) {
        0
    }
}
