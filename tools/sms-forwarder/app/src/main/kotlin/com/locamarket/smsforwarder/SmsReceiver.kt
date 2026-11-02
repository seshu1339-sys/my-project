package com.locamarket.smsforwarder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Android hands every incoming SMS to a receiver like this one; there is no way to ask only for one sender. So the first thing done here is
 * to compare the sender with the bank's IDs. Any other message is dropped on that line: its text is not read, kept or sent anywhere.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val sender = parts.firstOrNull()?.originatingAddress
        if (!SenderFilter.allowed(sender, SenderFilter.parse(Settings(context).senders))) return

        val input = Data.Builder()
            .putString(ForwardWorker.SENDER, sender)
            .putString(ForwardWorker.TEXT, parts.joinToString("") { it.messageBody.orEmpty() })
            .putLong(ForwardWorker.RECEIVED_AT, parts.first().timestampMillis)
            .build()
        val work = OneTimeWorkRequestBuilder<ForwardWorker>()
            .setInputData(input)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context).enqueue(work)
    }
}
