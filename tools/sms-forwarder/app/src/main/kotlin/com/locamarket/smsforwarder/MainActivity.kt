package com.locamarket.smsforwarder

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/** The settings screen: the endpoint, the token and the bank's sender IDs. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settings = Settings(this)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }

        fun box(label: String, value: String, secret: Boolean = false): EditText {
            page.addView(TextView(this).apply { text = label })
            val input = EditText(this).apply {
                setText(value)
                if (secret) inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
            page.addView(input)
            return input
        }

        val endpoint = box("Server link (smsIngest)", settings.endpoint)
        val token = box("Secret token", settings.token, secret = true)
        val senders = box("Bank sender IDs, separated by commas", settings.senders)
        page.addView(Button(this).apply {
            text = "Save"
            setOnClickListener {
                settings.endpoint = endpoint.text.toString()
                settings.token = token.text.toString()
                settings.senders = senders.text.toString()
                Toast.makeText(this@MainActivity, "Saved", Toast.LENGTH_SHORT).show()
            }
        })
        page.addView(TextView(this).apply {
            setPadding(0, pad, 0, 0)
            text = "Only SMS from the sender IDs above are sent to the server. Every other message is dropped without being read or kept. " +
                "Turn off battery optimisation for this app, or the phone may stop it."
        })
        setContentView(ScrollView(this).apply { addView(page) })

        if (checkSelfPermission(Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 1)
        }
    }
}
