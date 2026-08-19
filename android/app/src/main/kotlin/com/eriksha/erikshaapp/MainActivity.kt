package com.eriksha.erikshaapp

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.surepass.latlong.LatLongCallback
import io.surepass.latlong.LatLongConfig
import io.surepass.latlong.LatLongError
import io.surepass.latlong.LatLongResponse
import io.surepass.latlong.LatLongSdk
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Hosts the Flutter engine and bridges the Surepass send-location SDK
 * (`io.surepass.latlong`) to Flutter over a MethodChannel. Android-only — the
 * Field Investigation "Capture Current Location" button invokes `captureLocation`.
 *
 * Flow: check/request ACCESS_FINE_LOCATION at runtime (the headless SDK can't
 * show the dialog itself) → LatLongSdk.verifyLocation() → return the result map.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "eriksha/sendlocation"
    private val downloadsChannelName = "eriksha/downloads"
    private val locationReqCode = 8724
    private val notifReqCode = 8725

    // The SDK sends its verification server URL as the base; it appends the path.
    private val baseUrl = "https://n8n.surepass.io"

    // Held while the runtime permission dialog is up, replied to once resolved.
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureLocation" -> handleCapture(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePdf" -> handleSavePdf(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    // --- Downloads: save a PDF to the public Downloads + status-bar notification ---

    private fun handleSavePdf(call: MethodCall, result: MethodChannel.Result) {
        val rawName = call.argument<String>("filename") ?: "document.pdf"
        val name = if (rawName.endsWith(".pdf", true)) rawName else "$rawName.pdf"
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("NO_DATA", "No file data to save.", null)
            return
        }
        try {
            val saved = savePdfToDownloads(name, bytes)
            maybeRequestNotifPermission()
            showDownloadNotification(name, saved.uri, saved.location)
            // Return the human-readable save location (e.g. "Download/foo.pdf").
            result.success(saved.location)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message ?: "Could not save the file.", null)
        }
    }

    // Saved file's content uri (for tap-to-open) + a display location string.
    private data class SavedPdf(val uri: Uri?, val location: String)

    private fun savePdfToDownloads(name: String, bytes: ByteArray): SavedPdf {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // MediaStore → public Downloads (no storage permission needed).
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Could not create the download entry.")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IOException("Could not write the file.")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            // Lands in the phone's public "Download" folder.
            return SavedPdf(uri, "${Environment.DIRECTORY_DOWNLOADS}/$name")
        }
        // API < 29: app-specific external Downloads dir (no permission needed).
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IOException("Storage is not available.")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, name)
        FileOutputStream(file).use { it.write(bytes) }
        return SavedPdf(null, file.absolutePath)
    }

    private fun showDownloadNotification(name: String, uri: Uri?, location: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "downloads"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId, "Downloads", NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Download complete")
            .setContentText("Saved to $location")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Saved to $location"))
            .setAutoCancel(true)
        if (uri != null && uri.scheme == "content") {
            val open = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/pdf")
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK,
                )
            }
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            builder.setContentIntent(
                PendingIntent.getActivity(this, name.hashCode(), open, flags),
            )
        }
        nm.notify(name.hashCode(), builder.build())
    }

    private fun maybeRequestNotifPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), notifReqCode,
            )
        }
    }

    private fun handleCapture(result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            verifyLocation(result)
        } else {
            // Only one capture can be in flight; reject a second concurrent call.
            if (pendingResult != null) {
                result.error(
                    "IN_PROGRESS",
                    "A location capture is already in progress.",
                    null,
                )
                return
            }
            pendingResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                locationReqCode,
            )
        }
    }

    private fun verifyLocation(result: MethodChannel.Result) {
        LatLongSdk.verifyLocation(
            this,
            LatLongConfig(baseUrl),
            object : LatLongCallback {
                override fun onSuccess(response: LatLongResponse) {
                    val loc = response.location
                    Log.d(
                        "SendLocation",
                        "onSuccess → success=${response.success} " +
                            "statusCode=${response.statusCode} " +
                            "message=${response.message} id=${response.data?.id} " +
                            "lat=${loc.latitude} lng=${loc.longitude} " +
                            "address=${loc.address}",
                    )
                    result.success(
                        mapOf(
                            "success" to true,
                            "statusCode" to response.statusCode,
                            "message" to response.message,
                            "id" to response.data?.id,
                            // What the SDK captured + sent (reverse-geocoded).
                            "latitude" to loc.latitude,
                            "longitude" to loc.longitude,
                            "address" to loc.address,
                        ),
                    )
                }

                override fun onFailure(error: LatLongError) {
                    Log.d(
                        "SendLocation",
                        "onFailure → code=${error.code.name} " +
                            "message=${error.message} cause=${error.cause}",
                    )
                    result.success(
                        mapOf(
                            "success" to false,
                            "code" to error.code.name,
                            "message" to error.message,
                        ),
                    )
                }
            },
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != locationReqCode) return
        val result = pendingResult ?: return
        pendingResult = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            verifyLocation(result)
        } else {
            result.success(
                mapOf(
                    "success" to false,
                    "code" to "PERMISSION_DENIED",
                    "message" to
                        "Location permission is required to capture your location.",
                ),
            )
        }
    }
}
