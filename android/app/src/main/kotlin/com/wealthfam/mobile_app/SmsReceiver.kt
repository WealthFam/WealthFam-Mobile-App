package com.wealthfam.mobile_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import androidx.core.content.ContextCompat

class SmsReceiver : BroadcastReceiver() {
    private val TAG = "SmsReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            for (sms in messages) {
                val sender = sms.displayOriginatingAddress
                val body = sms.displayMessageBody
                
                val date = sms.timestampMillis
                
                Log.d(TAG, "SMS Received from $sender: $body (at $date)")

                // Start the native foreground service to handle the sync
                val serviceIntent = Intent(context, SmsProcessingService::class.java)
                serviceIntent.putExtra("sender", sender)
                serviceIntent.putExtra("message", body)
                serviceIntent.putExtra("date", date)
                
                try {
                    ContextCompat.startForegroundService(context, serviceIntent)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start foreground service: ${e.message}")
                }
            }
        }
    }
}
