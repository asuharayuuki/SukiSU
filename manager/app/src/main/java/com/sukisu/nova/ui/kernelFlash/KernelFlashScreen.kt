package com.sukisu.nova.ui.kernelFlash

import android.net.Uri
import android.os.Environment
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.navigationevent.NavigationEventInfo
import androidx.navigationevent.compose.NavigationBackHandler
import androidx.navigationevent.compose.rememberNavigationEventState
import com.sukisu.nova.R
import com.sukisu.nova.ui.LocalUiMode
import com.sukisu.nova.ui.UiMode
import com.sukisu.nova.ui.kernelFlash.state.HorizonKernelState
import com.sukisu.nova.ui.kernelFlash.state.HorizonKernelWorker
import com.sukisu.nova.ui.navigation3.LocalNavigator
import com.sukisu.nova.ui.util.reboot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun KernelFlashScreen(
    kernelUri: Uri,
    selectedSlot: String? = null,
    kpmPatchEnabled: Boolean = false,
    kpmUndoPatch: Boolean = false,
    onBackEnabledChange: (Boolean) -> Unit = {},
) {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val activity = LocalActivity.current
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()

    val horizonKernelState = remember(kernelUri, selectedSlot, kpmPatchEnabled, kpmUndoPatch) {
        if (KernelFlashStateHolder.currentState != null &&
            KernelFlashStateHolder.currentUri == kernelUri &&
            KernelFlashStateHolder.currentSlot == selectedSlot &&
            KernelFlashStateHolder.currentKpmPatchEnabled == kpmPatchEnabled &&
            KernelFlashStateHolder.currentKpmUndoPatch == kpmUndoPatch) {
            KernelFlashStateHolder.currentState!!
        } else {
            HorizonKernelState().also {
                KernelFlashStateHolder.currentState = it
                KernelFlashStateHolder.currentUri = kernelUri
                KernelFlashStateHolder.currentSlot = selectedSlot
                KernelFlashStateHolder.currentKpmPatchEnabled = kpmPatchEnabled
                KernelFlashStateHolder.currentKpmUndoPatch = kpmUndoPatch
            }
        }
    }

    val flashState by horizonKernelState.state.collectAsStateWithLifecycle()
    val backEnabled = !flashState.isFlashing

    SideEffect { onBackEnabledChange(backEnabled) }
    NavigationBackHandler(
        state = rememberNavigationEventState(NavigationEventInfo.None),
        isBackEnabled = !backEnabled,
        onBackCompleted = {},
    )
    DisposableEffect(horizonKernelState) {
        onDispose {
            if (activity?.isChangingConfigurations != true) {
                val current = horizonKernelState.state.value
                if (current.isCompleted || current.error.isNotEmpty()) {
                    KernelFlashStateHolder.clear()
                }
            }
        }
    }

    val flashComplete = stringResource(R.string.horizon_flash_complete)

    val logText = remember(flashState.logs, flashState.error, flashState.isCompleted, flashComplete) {
        buildString {
            append(flashState.logs.joinToString("\n"))
            if (flashState.error.isNotEmpty()) {
                append("\n${flashState.error}\n")
            } else if (flashState.isCompleted) {
                append("\n$flashComplete\n")
            }
        }
    }

    LaunchedEffect(horizonKernelState) {
        if (horizonKernelState.tryStartFlashing()) {
            try {
                HorizonKernelWorker(
                    context = context.applicationContext,
                    state = horizonKernelState,
                    uri = kernelUri,
                    slot = selectedSlot,
                    kpmPatchEnabled = kpmPatchEnabled,
                    kpmUndoPatch = kpmUndoPatch
                ).start()
            } catch (e: Exception) {
                horizonKernelState.setError(e.message ?: resources.getString(R.string.horizon_unknown_error))
            }
        }
    }

    val actions = KernelFlashActions(
        onBack = {
            if (!horizonKernelState.state.value.isFlashing) {
                if (flashState.isCompleted || flashState.error.isNotEmpty()) {
                    KernelFlashStateHolder.clear()
                }
                navigator.pop()
            }
        },
        onSaveLog = { logContentValue ->
            scope.launch(Dispatchers.IO) {
                val format = SimpleDateFormat("yyyy-MM-dd-HH-mm-ss", Locale.getDefault())
                val date = format.format(Date())
                val file = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "SukiSU_Nova_kernel_flash_log_${date}.log"
                )
                file.writeText(logContentValue)
            }
        },
        onReboot = {
            scope.launch {
                withContext(Dispatchers.IO) {
                    reboot()
                }
            }
        }
    )

    when (LocalUiMode.current) {
        UiMode.Miuix -> KernelFlashMiuix(
            state = flashState,
            actions = actions,
            logText = logText,
            kpmPatchEnabled = kpmPatchEnabled,
            kpmUndoPatch = kpmUndoPatch
        )

        UiMode.Material -> KernelFlashMaterial(
            state = flashState,
            actions = actions,
            logText = logText,
            kpmPatchEnabled = kpmPatchEnabled,
            kpmUndoPatch = kpmUndoPatch
        )
    }
}
