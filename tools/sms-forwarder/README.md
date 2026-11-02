# Local Market SMS Forwarder

A small Android app for the owner's own phone. It sends bank SMS to the `smsIngest` function, which keeps only the payment ID and amount.

What it can touch:

- It holds `RECEIVE_SMS` only, not `READ_SMS`, so it can never open the phone's inbox or read old messages.
- Android gives every incoming SMS to the app; there is no way to ask for one sender. The first line of `SmsReceiver` compares the sender with the IDs in Settings, and any other message is dropped there without its text being read.
- Nothing is stored on the phone apart from the settings.

Setting it up:

1. Build: `gradlew assembleDebug` here. The APK is `app/build/outputs/apk/debug/app-debug.apk`.
2. Install it on the phone that gets the HDFC SMS. Google Play does not allow this kind of SMS permission here, so it is installed directly and never uploaded.
3. Open it, allow SMS, and fill in the `smsIngest` link, the `SMS_INGEST_TOKEN` value and the bank's sender IDs.
4. Turn off battery optimisation for the app, or Android may stop it.
