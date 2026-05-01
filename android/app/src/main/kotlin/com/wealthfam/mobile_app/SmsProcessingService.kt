package com.wealthfam.mobile_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log
import androidx.preference.PreferenceManager
import org.json.JSONObject
import java.io.File

class SmsProcessingService : Service() {
    private val TAG = "SmsProcessingService"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val sender = intent?.getStringExtra("sender") ?: "Unknown"
        val message = intent?.getStringExtra("message") ?: ""
        val date = intent?.getLongExtra("date", System.currentTimeMillis()) ?: System.currentTimeMillis()
        
        // Android 8+ requirement: Must call startForeground even for short-lived relay
        val notification = NotificationCompat.Builder(this, "sms_channel")
            .setContentTitle("SMS Syncing")
            .setContentText("Processing message from $sender")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(998, notification)

        if (sender != "Unknown") {
            // Quick Location Capture (Best Effort)
            var lat: Double? = null
            var lng: Double? = null
            try {
                val locationManager = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
                val provider = android.location.LocationManager.GPS_PROVIDER
                val location = locationManager.getLastKnownLocation(provider) ?: 
                              locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)
                
                if (location != null) {
                    lat = location.latitude
                    lng = location.longitude
                    Log.d(TAG, "Native location captured: $lat, $lng")
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "Location permission missing in native layer")
            } catch (e: Exception) {
                Log.e(TAG, "Native location error: ${e.message}")
            }

            val timestamp = System.currentTimeMillis()
            val random = (0..999).random()
            val itemKey = "flutter.sms_relay_item_${timestamp}_$random"
            
            val json = JSONObject()
            json.put("sender", sender)
            json.put("message", message)
            json.put("date", date)
            if (lat != null) json.put("latitude", lat)
            if (lng != null) json.put("longitude", lng)

            val jsonStr = json.toString()

            try {
                val relayDir = File(filesDir, "sms_relay")
                if (!relayDir.exists()) relayDir.mkdirs()
                
                val relayFile = File(relayDir, "relay_${timestamp}_${random}.json")
                relayFile.writeText(jsonStr)
                Log.d(TAG, "SMS successfully relayed to file: ${relayFile.absolutePath}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to write relay file: ${e.message}")
            }
        }

        stopSelf()
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                "sms_channel",
                "SMS Processing Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
