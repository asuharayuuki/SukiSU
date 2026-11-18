package com.sukisu.nova.ui.util

import android.net.Uri
import android.os.Build
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import com.sukisu.nova.data.registry.ExpectedFile
import com.sukisu.nova.data.repository.SettingsRepositoryImpl
import com.sukisu.nova.data.update.UpdateSourceConfig
import com.sukisu.nova.data.update.UpdateSourceDefaults
import com.sukisu.nova.ksuApp
import com.sukisu.nova.ui.util.module.LatestVersionInfo
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * @author weishu
 * @date 2023/6/22.
 */
suspend fun download(
    url: String,
    fileName: String,
    onDownloaded: (Uri) -> Unit = {},
    onDownloading: () -> Unit = {},
    onProgress: (Int) -> Unit = {},
    expected: ExpectedFile? = null,
    onFailed: (DownloadManager.DownloadState) -> Unit = {},
) {
    onDownloading()

    val downloadId = DownloadManager.enqueue(
        context = ksuApp,
        url = url,
        fileName = fileName,
        onCompleted = onDownloaded,
        expected = expected,
    )

    val finalState = DownloadManager.downloads
        .onEach { map -> map[downloadId]?.let { onProgress(it.progress) } }
        .first { map ->
            val status = map[downloadId]?.status
            status == DownloadManager.Status.COMPLETED ||
                status == DownloadManager.Status.FAILED
        }[downloadId]
    if (finalState?.status == DownloadManager.Status.FAILED) {
        withContext(Dispatchers.Main) { onFailed(finalState) }
    }
}

internal suspend fun isDownloadAvailable(uri: Uri): Boolean = withContext(Dispatchers.IO) {
    runCatching {
        ksuApp.contentResolver.openFileDescriptor(uri, "r").use { it != null }
    }.getOrDefault(false)
}


suspend fun checkNewVersion(): LatestVersionInfo = checkReleaseVersion(isCi = false)

suspend fun checkNewCiVersion(): LatestVersionInfo = checkReleaseVersion(isCi = true)

/**
 * Update checks now run over the built-in source plus every enabled custom
 * source. A pinned source is tried first; when it fails the manager falls back
 * to racing the remaining sources and using the fastest answer.
 */
private suspend fun checkReleaseVersion(isCi: Boolean): LatestVersionInfo {
    if (!isNetworkAvailable(ksuApp)) return LatestVersionInfo()

    val settings = SettingsRepositoryImpl()
    val sources = buildList {
        addAll(UpdateSourceDefaults.BUILTIN_SOURCES)
        addAll(settings.updateSources.filter { it.enabled })
    }
    val pinnedId = settings.pinnedUpdateSourceId
    val pinned = sources.firstOrNull { it.id == pinnedId }

    if (pinned != null) {
        querySource(pinned, isCi)?.let { return it.info }
    }

    val candidates = sources.filter { pinned == null || it.id != pinned.id }
    if (candidates.isEmpty()) return LatestVersionInfo()
    return raceSources(candidates, isCi)
}

/**
 * Queries every candidate in parallel and returns the first successful answer.
 * Losing requests are cancelled so one dead mirror cannot delay the update
 * prompt until the HTTP timeout; since all requests start together, the first
 * success is also the lowest-latency source.
 */
private suspend fun raceSources(
    candidates: List<UpdateSourceConfig>,
    isCi: Boolean,
): LatestVersionInfo = coroutineScope {
    val results = Channel<TimedVersionInfo>(Channel.UNLIMITED)
    val queries = candidates.map { source ->
        launch(Dispatchers.IO) {
            querySource(source, isCi)?.let { results.trySend(it) }
        }
    }
    val closer = launch {
        queries.joinAll()
        results.close()
    }
    val fastest = try {
        results.receiveCatching().getOrNull()
    } finally {
        queries.forEach { it.cancel() }
        closer.cancel()
        results.close()
    }
    fastest?.let {
        android.util.Log.d(
            "UpdateCheck",
            "using ${it.info.sourceName.ifBlank { it.info.sourceId }} (${it.elapsedMs} ms)",
        )
    }
    fastest?.info ?: LatestVersionInfo()
}

private data class TimedVersionInfo(
    val info: LatestVersionInfo,
    val elapsedMs: Long,
)

private suspend fun querySource(
    source: UpdateSourceConfig,
    isCi: Boolean,
): TimedVersionInfo? {
    val started = System.nanoTime()
    return try {
        val info = fetchFromSource(source, isCi)
        info.takeIf { it.versionCode > 0L && it.downloadUrl.isNotBlank() }?.let {
            TimedVersionInfo(it, (System.nanoTime() - started) / 1_000_000)
        }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        android.util.Log.w("UpdateCheck", "${source.displayName}: update check failed", error)
        null
    }
}

private val updateHttpClient by lazy {
    ksuApp.okhttpClient.newBuilder()
        .callTimeout(10, TimeUnit.SECONDS)
        .build()
}

private suspend fun fetchFromSource(
    source: UpdateSourceConfig,
    isCi: Boolean,
): LatestVersionInfo {
    val endpoint = if (isCi) {
        "tags/${UpdateSourceDefaults.CI_TAG}"
    } else {
        UpdateSourceDefaults.STABLE_ENDPOINT
    }
    val request = Request.Builder()
        .url(source.releasesApiUrl(endpoint))
        .header("Accept", if (source.isGitHub) "application/vnd.github+json" else "application/json")
        .build()

    return suspendCancellableCoroutine { continuation ->
        val call = updateHttpClient.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resume(LatestVersionInfo())
            }

            override fun onResponse(call: Call, response: Response) {
                val info = try {
                    response.use { parseReleaseResponse(source, isCi, it) }
                } catch (error: Exception) {
                    android.util.Log.w(
                        "UpdateCheck",
                        "${source.displayName}: cannot parse release response",
                        error,
                    )
                    LatestVersionInfo()
                }
                if (continuation.isActive) continuation.resume(info)
            }
        })
    }
}

private fun parseReleaseResponse(
    source: UpdateSourceConfig,
    isCi: Boolean,
    response: Response,
): LatestVersionInfo {
    if (!response.isSuccessful) {
        android.util.Log.w("UpdateCheck", "${source.displayName}: HTTP ${response.code}")
        return LatestVersionInfo()
    }
    val json = JSONObject(response.body.string())
    val assets = json.getJSONArray("assets")
    val changelog = json.optString("body")
    val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: return LatestVersionInfo()
    val downloadPrefix = source.downloadUrlPrefix()

    if (isCi) {
        // The release title has been stale in the past (assets moved to a
        // newer build before the title did), so read the version from the
        // asset names instead of trusting the title.
        val apkPattern = Regex(
            """^SukiSU_Nova_.+_(\d+)-${Regex.escape(abi)}-release\.apk$"""
        )
        val apk = (0 until assets.length()).asSequence()
            .mapNotNull { assets.optJSONObject(it) }
            .mapNotNull { asset ->
                val match = apkPattern.matchEntire(asset.optString("name"))
                    ?: return@mapNotNull null
                match.groupValues[1].toLongOrNull()?.let { it to asset }
            }
            .maxByOrNull { it.first }
            ?: run {
                android.util.Log.w("UpdateCheck", "${source.displayName} CI: no APK for abi=$abi")
                return LatestVersionInfo()
            }
        val downloadUrl = apk.second.optString("browser_download_url")
            .takeIf { it.startsWith(downloadPrefix) }
            ?: return LatestVersionInfo()
        return LatestVersionInfo(
            versionCode = apk.first,
            downloadUrl = downloadUrl,
            changelog = changelog,
            sourceId = source.id,
            sourceName = source.displayName,
            downloadUrlPrefix = downloadPrefix,
        )
    }

    val archPattern = Regex("""^SukiSU_Nova_v(.+?)_(\d+)-${Regex.escape(abi)}-release\.apk$""")
    val universalPattern = Regex("""^SukiSU_Nova_v(.+?)_(\d+)-release\.apk$""")
    val apkAssets = (0 until assets.length()).map { assets.getJSONObject(it) }
    // Prefer the device-specific asset, falling back to an actual universal APK only.
    for (pattern in listOf(archPattern, universalPattern)) {
        for (asset in apkAssets) {
            val match = pattern.matchEntire(asset.getString("name")) ?: continue
            val downloadUrl = asset.getString("browser_download_url")
            if (!downloadUrl.startsWith(downloadPrefix)) continue
            return LatestVersionInfo(
                versionCode = match.groupValues[2].toLong(),
                downloadUrl = downloadUrl,
                changelog = changelog,
                sourceId = source.id,
                sourceName = source.displayName,
                downloadUrlPrefix = downloadPrefix,
            )
        }
    }
    return LatestVersionInfo()
}
