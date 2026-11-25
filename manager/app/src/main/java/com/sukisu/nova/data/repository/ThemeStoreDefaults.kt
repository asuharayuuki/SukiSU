package com.sukisu.nova.data.repository

/**
 * Built-in theme store sources. The first source is the fixed default used for
 * unset legacy settings. Other sources are selected only by an explicit choice.
 */
object ThemeStoreDefaults {
    private const val PRIMARY_BASE_URL = "https://theme.shirkneko.top/"
    private const val SECONDARY_BASE_URL = "https://themes.neko.shirkneko.top:8443/"

    /** Built-in sources shown in the source picker. */
    val BASE_URLS = listOf(PRIMARY_BASE_URL, SECONDARY_BASE_URL)

    /** Fixed default source used when upgrading from an unset setting. */
    fun preferredBaseUrl(): String = BASE_URLS.first()

    /**
     * The effective default source. An unset legacy value resolves to the fixed
     * default, while a configured source is used exactly as stored.
     */
    fun resolveConfiguredBaseUrl(configured: String): String {
        val trimmed = configured.trim()
        return trimmed.ifEmpty { preferredBaseUrl() }
    }
}
