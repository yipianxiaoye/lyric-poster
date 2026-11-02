package com.lyricposter.lyric_poster

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.lyricposter/update_installer"
    private var pendingApkPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingApkPath = savedInstanceState?.getString("pending_update_apk")
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("pending_update_apk", pendingApkPath)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_apk", "APK path is missing", null)
                    return@setMethodCallHandler
                }

                try {
                    val apk = validateApk(path)
                    if (requiresInstallPermission()) {
                        pendingApkPath = apk.absolutePath
                        openInstallPermissionSettings()
                        result.success("permission_required")
                    } else {
                        pendingApkPath = null
                        launchPackageInstaller(apk)
                        result.success("installer_launched")
                    }
                } catch (error: Exception) {
                    pendingApkPath = null
                    result.error("install_failed", error.message, null)
                }
            }
    }

    override fun onResume() {
        super.onResume()
        val path = pendingApkPath ?: return
        if (requiresInstallPermission()) return

        pendingApkPath = null
        try {
            launchPackageInstaller(validateApk(path))
        } catch (_: Exception) {
            // The next explicit update attempt can report an actionable error.
        }
    }

    private fun requiresInstallPermission(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        }
    }

    private fun validateApk(path: String): File {
        val updateCache = File(cacheDir, "update").canonicalFile
        val apk = File(path).canonicalFile
        if (!apk.path.startsWith(updateCache.path + File.separator) ||
            !apk.isFile || !apk.name.endsWith(".apk", ignoreCase = true)
        ) {
            throw IllegalArgumentException("The update APK must be inside the app update cache")
        }
        return apk
    }

    private fun launchPackageInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
    }
}
