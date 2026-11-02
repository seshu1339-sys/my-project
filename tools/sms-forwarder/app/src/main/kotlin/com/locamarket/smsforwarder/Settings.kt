package com.locamarket.smsforwarder

import android.content.Context

/** What the owner types in the app: the endpoint, its secret token and the bank's sender IDs. Kept in this app's private storage, never in the code. */
class Settings(context: Context) {
    private val saved = context.getSharedPreferences("forwarder", Context.MODE_PRIVATE)

    var endpoint: String
        get() = saved.getString("endpoint", "").orEmpty()
        set(value) = saved.edit().putString("endpoint", value.trim()).apply()

    var token: String
        get() = saved.getString("token", "").orEmpty()
        set(value) = saved.edit().putString("token", value.trim()).apply()

    var senders: String
        get() = saved.getString("senders", "").orEmpty()
        set(value) = saved.edit().putString("senders", value.trim()).apply()
}
