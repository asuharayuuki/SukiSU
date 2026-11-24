package com.sukisu.nova.data.repository

import java.util.concurrent.ConcurrentHashMap

/**
 * The built-in theme store mirrors. All hosts serve the same catalog, so the
 * selection never depends on the device region, locale or time zone: the first
 * mirror that is not cooling down is used, and a mirror that just failed steps
 * aside until the cooldown expires.
 */
object ThemeStoreDefaults {
    private const val PRIMARY_BASE_URL = "https://theme.shirkneko.top/"
    private const val SECONDARY_BASE_URL = "https://theme1.shirkneko.top/"
    private const val TERTIARY_BASE_URL = "https://theme2.shirkneko.top/"

    /** Built-in mirrors in failover order: primary, then secondary, then tertiary. */
    val BASE_URLS = listOf(PRIMARY_BASE_URL, SECONDARY_BASE_URL, TERTIARY_BASE_URL)

    /**
     * Mirrors shipped by earlier builds. A stored default that points at one of
     * them is treated as unset so the app moves to the current mirrors.
     */
    private val RETIRED_BASE_URLS = listOf(
        "https://themes.oddnexus.top/",
        "https://themes.neko.shirkneko.top:8443/",
        "https://themes.zako.shirkneko.top:20005/",
        "https://themes.shirkneko.top:41112/",
    )

    /** How long a failed mirror stays out of automatic selection. */
    private const val FAILOVER_COOLDOWN_MS = 30 * 60 * 1000L

    /** Normalized mirror URL to the time until which it is skipped by auto selection. */
    private val unavailableUntilMs = ConcurrentHashMap<String, Long>()

    /** The first mirror that is not cooling down, or the primary if all are. */
    fun preferredBaseUrl(): String {
        val now = System.currentTimeMillis()
        return BASE_URLS.firstOrNull { isAvailable(it, now) } ?: BASE_URLS.first()
    }

    private fun isAvailable(baseUrl: String, now: Long): Boolean {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(baseUrl) ?: return true
        return (unavailableUntilMs[normalized] ?: 0L) <= now
    }

    /**
     * The next built-in mirror to try when [baseUrl] cannot be reached, or null
     * when the URL is not a built-in mirror or has nothing after it.
     */
    fun fallbackBaseUrl(baseUrl: String): String? {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(baseUrl) ?: return null
        val mirrors = BASE_URLS.mapNotNull { ThemeStoreRepository.normalizeBaseUrl(it) }
        val index = mirrors.indexOf(normalized)
        return if (index < 0) null else mirrors.getOrNull(index + 1)
    }

    /**
     * Marks a built-in mirror as unreachable so automatic selection skips it for
     * [FAILOVER_COOLDOWN_MS]. It is retried after the cooldown without any
     * background probing.
     */
    fun reportUnreachable(baseUrl: String) {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(baseUrl) ?: return
        if (!isBuiltInBaseUrl(normalized)) return
        unavailableUntilMs[normalized] = System.currentTimeMillis() + FAILOVER_COOLDOWN_MS
    }

    /** Clears the failover state once a request to the marked mirror succeeds. */
    fun reportReachable(baseUrl: String) {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(baseUrl) ?: return
        unavailableUntilMs.remove(normalized)
    }

    /** True when [raw] points at one of the built-in mirrors. */
    fun isBuiltInBaseUrl(raw: String): Boolean {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(raw) ?: return false
        return BASE_URLS.any { base -> ThemeStoreRepository.normalizeBaseUrl(base) == normalized }
    }

    /** True when [raw] points at a mirror that an earlier build shipped. */
    fun isRetiredBaseUrl(raw: String): Boolean {
        val normalized = ThemeStoreRepository.normalizeBaseUrl(raw) ?: return false
        return RETIRED_BASE_URLS.any { base ->
            ThemeStoreRepository.normalizeBaseUrl(base) == normalized
        }
    }

    /**
     * True when the user has not pinned a mirror. An empty value follows the
     * built-in failover order; anything else is a manual choice.
     */
    fun usesAutoBaseUrl(configured: String): Boolean = configured.trim().isEmpty()

    /**
     * The effective default source: a manually selected mirror is used exactly
     * as stored. A blank value resolves to the best built-in mirror.
     */
    fun resolveConfiguredBaseUrl(configured: String): String {
        val trimmed = configured.trim()
        return trimmed.ifEmpty { preferredBaseUrl() }
    }

    /** The default mirror, resolved without any device-region lookup. */
    fun resolveBestBaseUrl(): String = preferredBaseUrl()
}
