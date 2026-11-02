package com.example.icon_shift

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/** An `<activity-alias>` carrying `icon_shift.variant` meta-data. */
data class AliasInfo(
    val component: ComponentName,
    val variantId: String,
    val label: String,
    val enabledInManifest: Boolean,
)

/** Reads and changes the app's IconShift activity-aliases. */
class AliasRegistry(private val context: Context) {
    companion object {
        const val META_VARIANT = "icon_shift.variant"
    }

    private val pm: PackageManager get() = context.packageManager
    private val packageName: String get() = context.packageName

    fun aliases(): List<AliasInfo> {
        @Suppress("DEPRECATION")
        val flags = PackageManager.GET_ACTIVITIES or
            PackageManager.GET_META_DATA or
            PackageManager.MATCH_DISABLED_COMPONENTS
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, flags)
        }
        return info.activities.orEmpty().mapNotNull { activity ->
            val variantId = activity.metaData?.getString(META_VARIANT) ?: return@mapNotNull null
            AliasInfo(
                component = ComponentName(packageName, activity.name),
                variantId = variantId,
                label = activity.loadLabel(pm).toString(),
                enabledInManifest = activity.enabled,
            )
        }
    }

    fun isEnabled(alias: AliasInfo): Boolean =
        when (pm.getComponentEnabledSetting(alias.component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias.enabledInManifest
            else -> false
        }

    fun states(aliases: List<AliasInfo>): List<AliasState> =
        aliases.map { AliasState(it.component.className, it.variantId, isEnabled(it)) }

    /**
     * Applies [steps] with DONT_KILL_APP. On Android 13+ all changes are sent
     * in one call; before that, in order (target enabled first).
     */
    fun apply(steps: List<SwitchStep>) {
        fun state(enable: Boolean) =
            if (enable) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.setComponentEnabledSettings(
                steps.map {
                    PackageManager.ComponentEnabledSetting(
                        ComponentName(packageName, it.componentName),
                        state(it.enable),
                        PackageManager.DONT_KILL_APP,
                    )
                },
            )
        } else {
            steps.forEach {
                pm.setComponentEnabledSetting(
                    ComponentName(packageName, it.componentName),
                    state(it.enable),
                    PackageManager.DONT_KILL_APP,
                )
            }
        }
    }

    /** Enabled launcher entries of this app that are not IconShift aliases. */
    fun foreignLauncherEntries(aliases: List<AliasInfo>): List<String> {
        val aliasNames = aliases.map { it.component.className }.toSet()
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setPackage(packageName)
        @Suppress("DEPRECATION")
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            pm.queryIntentActivities(intent, 0)
        }
        return resolved.map { it.activityInfo.name }.filter { it !in aliasNames }
    }
}
