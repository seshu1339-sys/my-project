package com.locamarket.smsforwarder

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Sends one bank SMS to the server, and tries again later if the phone or the server was not reachable. */
class ForwardWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val settings = Settings(applicationContext)
        if (settings.endpoint.isEmpty() || settings.token.isEmpty()) return Result.failure()
        val body = JSONObject()
            .put("sender", inputData.getString(SENDER))
            .put("text", inputData.getString(TEXT))
            .put("receivedAt", inputData.getLong(RECEIVED_AT, 0))
            .toString()
        return try {
            val connection = URL(settings.endpoint).openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 20000
            connection.readTimeout = 20000
            connection.setRequestProperty("Authorization", "Bearer ${settings.token}")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray()) }
            val code = connection.responseCode
            connection.disconnect()
            when {
                code in 200..299 -> Result.success()
                code == 401 -> Result.failure()
                else -> Result.retry()
            }
        } catch (_: java.io.IOException) {
            Result.retry()
        }
    }

    companion object {
        const val SENDER = "sender"
        const val TEXT = "text"
        const val RECEIVED_AT = "receivedAt"
    }
}
