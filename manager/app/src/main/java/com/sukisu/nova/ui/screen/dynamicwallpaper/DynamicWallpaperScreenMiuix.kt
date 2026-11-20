package com.sukisu.nova.ui.screen.dynamicwallpaper

import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material.icons.rounded.Wallpaper
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sukisu.nova.R
import com.sukisu.nova.ui.component.background.DynamicWallpaperFit
import com.sukisu.nova.ui.component.miuix.AppCard
import com.sukisu.nova.ui.util.ImageStorage
import top.yukonga.miuix.kmp.basic.Button
import top.yukonga.miuix.kmp.basic.ButtonDefaults
import top.yukonga.miuix.kmp.basic.HorizontalDivider
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.IconButton
import top.yukonga.miuix.kmp.basic.LinearProgressIndicator
import top.yukonga.miuix.kmp.basic.Switch
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.basic.TextButton
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Back
import top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme
import top.yukonga.miuix.kmp.window.WindowDialog

@Composable
fun DynamicWallpaperScreenMiuix(
    state: DynamicWallpaperPreviewUiState,
    actions: DynamicWallpaperPreviewActions,
) {
    val context = LocalContext.current
    val layoutDirection = LocalLayoutDirection.current
    val sizeLabel = if (state.sizeBytes > 0L) {
        Formatter.formatShortFileSize(context, state.sizeBytes)
    } else {
        ""
    }
    val formatLabel = when (state.kind) {
        ImageStorage.DynamicWallpaperKind.MP4 -> stringResource(R.string.dynamic_wallpaper_format_mp4)
        ImageStorage.DynamicWallpaperKind.WEBP -> stringResource(R.string.dynamic_wallpaper_format_webp)
        null -> ""
    }
    val hasPreview = state.previewPath != null
    val mediaVisible = hasPreview && !state.rendererFailed
    val topBarContentColor = if (mediaVisible) Color.White else colorScheme.onSurface
    val topBarSecondaryColor = if (mediaVisible) {
        Color.White.copy(alpha = 0.76f)
    } else {
        colorScheme.onSurfaceVariantSummary
    }
    val canPick = !state.busy
    val maxPanelHeight = with(LocalDensity.current) {
        maxOf(180.dp, LocalWindowInfo.current.containerSize.height.toDp() * 0.55f)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(if (mediaVisible) Color.Transparent else colorScheme.surface)
    ) {
        // Keeps the floating top bar readable over both bright and dark media.
        if (mediaVisible) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            0f to Color.Black.copy(alpha = 0.52f),
                            0.18f to Color.Black.copy(alpha = 0.12f),
                            0.62f to Color.Transparent,
                            0.82f to Color.Black.copy(alpha = 0.24f),
                            1f to Color.Black.copy(alpha = 0.62f),
                        )
                    )
            )
        }

        if (!mediaVisible) {
            EmptyPreview(
                rendererFailed = state.rendererFailed,
                error = state.rendererError,
                onRetry = actions.onRetryRenderer,
                contentColor = topBarContentColor,
                secondaryColor = topBarSecondaryColor,
                modifier = Modifier.align(Alignment.Center),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = actions.onBack, enabled = !state.busy) {
                    Icon(
                        modifier = Modifier.graphicsLayer {
                            if (layoutDirection == LayoutDirection.Rtl) scaleX = -1f
                        },
                        imageVector = MiuixIcons.Back,
                        contentDescription = stringResource(R.string.log_viewer_back),
                        tint = topBarContentColor,
                    )
                }
                Text(
                    text = stringResource(R.string.dynamic_wallpaper_title),
                    color = topBarContentColor,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 2.dp),
                )
                Spacer(Modifier.weight(1f))
                if (state.hasStaged) {
                    Text(
                        text = stringResource(R.string.dynamic_wallpaper_pending),
                        color = topBarContentColor,
                        fontSize = 13.sp,
                        modifier = Modifier
                            .clip(androidx.compose.foundation.shape.RoundedCornerShape(50))
                            .background(
                                if (mediaVisible) {
                                    Color.White.copy(alpha = 0.18f)
                                } else {
                                    colorScheme.surfaceContainerHigh
                                }
                            )
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                    )
                    Spacer(Modifier.width(12.dp))
                }
            }

            Spacer(Modifier.weight(1f))

            AppCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                insideMargin = PaddingValues(0.dp),
            ) {
                Column(
                    modifier = Modifier
                        .heightIn(max = maxPanelHeight)
                        .verticalScroll(rememberScrollState())
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Rounded.PlayCircle,
                            contentDescription = null,
                            tint = colorScheme.primary,
                            modifier = Modifier.size(30.dp),
                        )
                        Spacer(Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(
                                    if (state.hasStaged) {
                                        R.string.dynamic_wallpaper_pending_title
                                    } else {
                                        R.string.dynamic_wallpaper_title
                                    }
                                ),
                                style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.title3,
                                fontWeight = FontWeight.SemiBold,
                            )
                            val detail = listOfNotNull(
                                formatLabel.takeIf { it.isNotEmpty() },
                                sizeLabel.takeIf { it.isNotEmpty() },
                            ).joinToString(" · ")
                            Text(
                                text = detail.ifEmpty {
                                    stringResource(R.string.dynamic_wallpaper_empty_summary)
                                },
                                style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.body2,
                                color = colorScheme.onSurfaceVariantSummary,
                            )
                        }
                    }

                    if (state.busy) {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    }

                    if (state.kind == ImageStorage.DynamicWallpaperKind.MP4 && !state.isCard) {
                        HorizontalDivider()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = if (state.muted) {
                                    Icons.AutoMirrored.Rounded.VolumeOff
                                } else {
                                    Icons.AutoMirrored.Rounded.VolumeUp
                                },
                                contentDescription = null,
                                tint = colorScheme.onSurfaceVariantSummary,
                                modifier = Modifier.size(22.dp),
                            )
                            Spacer(Modifier.width(10.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = stringResource(R.string.dynamic_wallpaper_mute),
                                    style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.body1,
                                )
                                Text(
                                    text = stringResource(R.string.dynamic_wallpaper_mute_summary),
                                    style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                                    color = colorScheme.onSurfaceVariantSummary,
                                )
                            }
                            Switch(
                                checked = state.muted,
                                onCheckedChange = actions.onSetMuted,
                                enabled = !state.busy,
                            )
                        }
                        HorizontalDivider()
                    }

                    Text(
                        text = stringResource(R.string.dynamic_wallpaper_scale),
                        style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                        color = colorScheme.onSurfaceVariantSummary,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        ScalingChip(
                            label = stringResource(R.string.dynamic_wallpaper_fit_fit),
                            selected = state.transform.fit == DynamicWallpaperFit.FIT,
                            enabled = !state.busy,
                            onClick = { actions.onSelectFit(DynamicWallpaperFit.FIT) },
                            modifier = Modifier.weight(1f),
                        )
                        ScalingChip(
                            label = stringResource(R.string.dynamic_wallpaper_fit_fill),
                            selected = state.transform.fit == DynamicWallpaperFit.FILL,
                            enabled = !state.busy,
                            onClick = { actions.onSelectFit(DynamicWallpaperFit.FILL) },
                            modifier = Modifier.weight(1f),
                        )
                        ScalingChip(
                            label = stringResource(R.string.dynamic_wallpaper_fit_custom),
                            selected = state.transform.fit == DynamicWallpaperFit.CUSTOM,
                            enabled = !state.busy,
                            onClick = { actions.onSelectFit(DynamicWallpaperFit.CUSTOM) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (state.transform.fit == DynamicWallpaperFit.CUSTOM) {
                        Text(
                            text = stringResource(R.string.dynamic_wallpaper_adjust_hint),
                            style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                            color = colorScheme.onSurfaceVariantSummary,
                        )
                    }

                    Text(
                        text = stringResource(R.string.dynamic_wallpaper_frame_rate),
                        style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                        color = colorScheme.onSurfaceVariantSummary,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        ScalingChip(
                            label = stringResource(R.string.dynamic_wallpaper_frame_rate_auto),
                            selected = state.fps == 0,
                            enabled = !state.busy,
                            onClick = { actions.onSetFps(0) },
                            modifier = Modifier.weight(1f),
                        )
                        listOf(24, 30, 60).forEach { value ->
                            ScalingChip(
                                label = value.toString(),
                                selected = state.fps == value,
                                enabled = !state.busy,
                                onClick = { actions.onSetFps(value) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }

                    if (state.kind == ImageStorage.DynamicWallpaperKind.MP4) {
                        Text(
                            text = stringResource(R.string.dynamic_wallpaper_playback_speed),
                            style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                            color = colorScheme.onSurfaceVariantSummary,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf(0.5f, 1f, 1.5f, 2f).forEach { value ->
                                ScalingChip(
                                    label = if (value == 1f) "1×" else "${value}×",
                                    selected = kotlin.math.abs(state.speed - value) < 0.01f,
                                    enabled = !state.busy,
                                    onClick = { actions.onSetSpeed(value) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                        Text(
                            text = stringResource(R.string.dynamic_wallpaper_playback_scope),
                            style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                            color = colorScheme.onSurfaceVariantSummary,
                        )
                    }

                    if (state.hasStaged) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            TextButton(
                                text = stringResource(R.string.dynamic_wallpaper_discard),
                                onClick = actions.onDiscardStaged,
                                enabled = !state.busy,
                                modifier = Modifier.weight(1f),
                            )
                            Button(
                                onClick = actions.onApply,
                                enabled = !state.busy,
                                modifier = Modifier.weight(1f),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.CheckCircleOutline,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = stringResource(R.string.dynamic_wallpaper_apply),
                                    fontSize = 15.sp,
                                )
                            }
                        }
                    } else {
                        Button(
                            onClick = actions.onPick,
                            enabled = canPick,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Wallpaper,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                text = stringResource(
                                    if (state.hasSaved) {
                                        R.string.dynamic_wallpaper_replace
                                    } else {
                                        R.string.dynamic_wallpaper_pick
                                    }
                                ),
                                fontSize = 15.sp,
                            )
                        }
                        if (state.hasSaved) {
                            TextButton(
                                text = stringResource(R.string.dynamic_wallpaper_remove),
                                onClick = actions.onRequestRemove,
                                enabled = !state.busy,
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.textButtonColors(
                                    color = Color.Transparent,
                                    textColor = colorScheme.error,
                                ),
                            )
                        }
                    }

                    Text(
                        text = stringResource(R.string.dynamic_wallpaper_limit),
                        style = top.yukonga.miuix.kmp.theme.MiuixTheme.textStyles.footnote2,
                        color = colorScheme.onSurfaceVariantSummary,
                    )
                }
            }
        }
    }

    if (state.showRemoveConfirm) {
        WindowDialog(
            show = true,
            title = stringResource(R.string.dynamic_wallpaper_remove_title),
            onDismissRequest = actions.onDismissRemove,
            content = {
                Column(
                    modifier = Modifier.padding(horizontal = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(stringResource(R.string.dynamic_wallpaper_remove_message))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        TextButton(
                            text = stringResource(android.R.string.cancel),
                            onClick = actions.onDismissRemove,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(
                            text = stringResource(R.string.dynamic_wallpaper_remove),
                            onClick = actions.onConfirmRemove,
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.textButtonColors(
                                color = colorScheme.error,
                                textColor = colorScheme.onError,
                            ),
                        )
                    }
                }
            },
        )
    }
}

@Composable
private fun EmptyPreview(
    rendererFailed: Boolean,
    error: String,
    onRetry: () -> Unit,
    contentColor: Color,
    secondaryColor: Color,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(horizontal = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Rounded.PlayCircle,
            contentDescription = null,
            tint = contentColor.copy(alpha = 0.9f),
            modifier = Modifier.size(56.dp),
        )
        Text(
            text = stringResource(
                if (rendererFailed) {
                    R.string.dynamic_wallpaper_preview_failed_title
                } else {
                    R.string.dynamic_wallpaper_empty_title
                }
            ),
            color = contentColor,
            fontSize = 18.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(
                if (rendererFailed) {
                    R.string.dynamic_wallpaper_preview_failed_summary
                } else {
                    R.string.dynamic_wallpaper_empty_summary
                }
            ),
            color = secondaryColor,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
        )
        if (rendererFailed && error.isNotBlank()) {
            Text(
                text = error,
                color = contentColor.copy(alpha = 0.62f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                maxLines = 3,
            )
        }
        if (rendererFailed) {
            TextButton(
                text = stringResource(R.string.dynamic_wallpaper_retry),
                onClick = onRetry,
                colors = ButtonDefaults.textButtonColors(
                    color = contentColor.copy(alpha = 0.16f),
                    textColor = contentColor,
                ),
            )
        }
    }
}

@Composable
private fun ScalingChip(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TextButton(
        text = label,
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        colors = if (selected) {
            ButtonDefaults.textButtonColorsPrimary()
        } else {
            ButtonDefaults.textButtonColors()
        },
    )
}
