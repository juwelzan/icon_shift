package com.example.icon_shift

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.PersistableBundle

/** Outcome of a shortcut change, mapped to the method channel by the plugin. */
internal sealed class ShortcutResult {
    /** [status] is `applied`, `unchanged` or `pending`. */
    data class Ok(val status: String, val message: String? = null) : ShortcutResult()

    data class Failed(val code: String, val message: String) : ShortcutResult()
}

/**
 * A home-screen shortcut that carries any name and any icon.
 *
 * The app's own launcher label and icon are compiled into activity-aliases,
 * so a name typed by the user or an image downloaded from a server can never
 * become the app entry itself. A pinned shortcut can: the launcher asks the
 * user once to place it, and after that its label and icon are updated
 * silently, as often as wanted.
 *
 * Needs Android 8.0 (API 26) for `requestPinShortcut` and a launcher that
 * supports pinning.
 */
internal class ShortcutIdentity(private val context: Context) {
    companion object {
        /** Id of the one shortcut IconShift owns. */
        const val ID = "icon_shift_identity"
        const val EXTRA_ICON_KEY = "icon_shift.icon_key"
        const val MIN_SDK = Build.VERSION_CODES.O
    }

    private val manager: ShortcutManager?
        get() = if (Build.VERSION.SDK_INT >= MIN_SDK) {
            context.getSystemService(ShortcutManager::class.java)
        } else {
            null
        }

    /** Whether this device and launcher can pin shortcuts. */
    private val canPin: Boolean
        get() = manager?.isRequestPinShortcutSupported == true

    private fun pinned(): ShortcutInfo? =
        manager?.pinnedShortcuts?.firstOrNull { it.id == ID }

    fun state(): Map<String, Any?> {
        val info = pinned()
        return mapOf(
            "supported" to canPin,
            "pinned" to (info != null),
            "name" to info?.shortLabel?.toString(),
            "iconKey" to info?.extras?.getString(EXTRA_ICON_KEY),
            "limitation" to limitation(),
        )
    }

    fun limitation(): String? = when {
        Build.VERSION.SDK_INT < MIN_SDK ->
            "Home-screen shortcuts need Android 8.0 (API 26); this device runs API ${Build.VERSION.SDK_INT}."
        manager == null -> "This device has no ShortcutManager."
        !canPin ->
            "The current launcher does not support pinned shortcuts. The user can switch launcher, " +
                "or add the shortcut from the launcher's own widget/shortcut list."
        else ->
            "Shows a shortcut next to the app entry, not instead of it: the app itself keeps the name " +
                "and icon compiled into the build (visible in the app drawer and settings). The first " +
                "call asks the user to place the shortcut; later changes are silent. A few launchers " +
                "only pick up a new label or icon after a reboot."
    }

    /**
     * Creates the shortcut, or updates the pinned one. [name] and [bytes] fall
     * back to what the shortcut already shows, so either can change alone.
     */
    fun set(name: String?, bytes: ByteArray?, iconKey: String?): ShortcutResult {
        if (manager == null || Build.VERSION.SDK_INT < MIN_SDK) {
            return ShortcutResult.Failed("unsupported", limitation()!!)
        }
        val existing = pinned()
        val label = name ?: existing?.shortLabel?.toString() ?: appLabel()
        if (label.isBlank()) {
            return ShortcutResult.Failed("invalid_argument", "The shortcut name must not be blank.")
        }
        val icon = if (bytes == null) {
            null
        } else {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return ShortcutResult.Failed(
                    "invalid_argument",
                    "The icon bytes could not be decoded as an image.",
                )
            Icon.createWithBitmap(bitmap)
        }
        if (existing != null &&
            icon == null &&
            label == existing.shortLabel?.toString() &&
            iconKey == existing.extras?.getString(EXTRA_ICON_KEY)
        ) {
            return ShortcutResult.Ok("unchanged")
        }

        val builder = ShortcutInfo.Builder(context, ID)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIntent(launchIntent())
        if (icon != null) builder.setIcon(icon)
        if (iconKey != null) {
            builder.setExtras(PersistableBundle().apply { putString(EXTRA_ICON_KEY, iconKey) })
        }
        val info = builder.build()

        return try {
            if (existing != null) {
                // Pinned shortcuts are mutable: no dialog, no user action.
                if (manager!!.updateShortcuts(listOf(info))) {
                    ShortcutResult.Ok("applied", "The pinned shortcut now shows \"$label\".")
                } else {
                    ShortcutResult.Failed(
                        "native_failure",
                        "The launcher refused to update the shortcut. It may have reached its " +
                            "shortcut limit, or the shortcut is rate-limited; try again later.",
                    )
                }
            } else if (!canPin) {
                ShortcutResult.Failed("unsupported", limitation()!!)
            } else {
                manager!!.requestPinShortcut(info, null)
                ShortcutResult.Ok(
                    "pending",
                    "The system asked the user to add the shortcut \"$label\" to the home screen. " +
                        "Call getShortcutIdentity() afterwards to see whether they accepted.",
                )
            }
        } catch (e: IllegalStateException) {
            // Thrown in the background, or for a locked/non-foreground user.
            ShortcutResult.Failed(
                "not_active",
                "Android only shows the pin request while the app is in the foreground: ${e.message}",
            )
        }
    }

    /**
     * Disables the pinned shortcut: the launcher greys it out and shows
     * [message] when it is tapped. Only the user can remove it from the home
     * screen; no app may do that.
     */
    fun disable(message: String): ShortcutResult {
        val manager = manager ?: return ShortcutResult.Failed("unsupported", limitation()!!)
        if (pinned() == null) return ShortcutResult.Ok("unchanged")
        manager.disableShortcuts(listOf(ID), message)
        return ShortcutResult.Ok(
            "applied",
            "The shortcut is disabled. It stays on the home screen, greyed out, until the user " +
                "removes it; setShortcutIdentity() enables it again.",
        )
    }

    private fun appLabel(): String =
        context.applicationInfo.loadLabel(context.packageManager).toString()

    /**
     * What the shortcut opens. It targets the real activity behind the
     * IconShift aliases, so switching variants (which disables aliases) never
     * breaks the shortcut.
     */
    private fun launchIntent(): Intent {
        val pm = context.packageManager
        val target = AliasRegistry(context).aliases().firstNotNullOfOrNull { it.targetActivity }
        val intent = if (target != null) {
            Intent(Intent.ACTION_MAIN).setComponent(ComponentName(context.packageName, target))
        } else {
            pm.getLaunchIntentForPackage(context.packageName)
                ?.setAction(Intent.ACTION_MAIN)
                ?: Intent(Intent.ACTION_MAIN).setPackage(context.packageName)
        }
        return intent
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
}
