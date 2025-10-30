package com.upsc

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private lateinit var audioWakeLockManager: AudioWakeLockManager
    private val CHANNEL = "com.upsc/audio_device"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioWakeLockManager = AudioWakeLockManager(this)
        audioWakeLockManager.setupChannel(flutterEngine)
        
        // Setup audio device detection channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentAudioDevice" -> {
                    val deviceInfo = getCurrentAudioDevice()
                    result.success(deviceInfo)
                }
                "getAvailableAudioDevices" -> {
                    val devices = getAvailableAudioDevices()
                    result.success(devices)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getCurrentAudioDevice(): Map<String, Any> {
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val result = mutableMapOf<String, Any>()
        
        try {
            // Check if Bluetooth SCO is on
            val isBluetoothScoOn = audioManager.isBluetoothScoOn
            val isBluetoothA2dpOn = audioManager.isBluetoothA2dpOn
            val isSpeakerphoneOn = audioManager.isSpeakerphoneOn
            
            result["isBluetoothScoOn"] = isBluetoothScoOn
            result["isBluetoothA2dpOn"] = isBluetoothA2dpOn
            result["isSpeakerphoneOn"] = isSpeakerphoneOn
            
            // Determine current device type
            val deviceType = when {
                isBluetoothScoOn || isBluetoothA2dpOn -> "Bluetooth"
                isSpeakerphoneOn -> "Speaker"
                else -> "Earpiece"
            }
            result["currentDevice"] = deviceType
            
            // Get available devices (Android 6.0+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val deviceList = devices.map { device ->
                    mapOf(
                        "type" to getDeviceTypeName(device.type),
                        "name" to device.productName.toString()
                    )
                }
                result["availableDevices"] = deviceList
            }
            
        } catch (e: Exception) {
            result["error"] = e.message ?: "Unknown error"
            result["currentDevice"] = "Unknown"
        }
        
        return result
    }
    
    private fun getAvailableAudioDevices(): List<Map<String, Any>> {
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val deviceList = mutableListOf<Map<String, Any>>()
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                devices.forEach { device ->
                    deviceList.add(mapOf(
                        "type" to getDeviceTypeName(device.type),
                        "name" to device.productName.toString(),
                        "id" to device.id
                    ))
                }
            }
        } catch (e: Exception) {
            // Return empty list on error
        }
        
        return deviceList
    }
    
    private fun getDeviceTypeName(type: Int): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            when (type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth"
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
                AudioDeviceInfo.TYPE_USB_DEVICE -> "USB"
                AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
                else -> "Unknown"
            }
        } else {
            "Unknown"
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            
            // High importance channel for messages
            val channelId = "high_importance_channel"
            val channelName = "Messages"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = "Instant message notifications"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
}
