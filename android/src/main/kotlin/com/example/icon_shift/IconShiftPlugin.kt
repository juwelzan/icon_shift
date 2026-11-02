package com.example.icon_shift

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android implementation of IconShift.
 *
 * Each variant is an `<activity-alias>` with its own icon and label and the
 * meta-data `icon_shift.variant`; exactly one is enabled at a time. See
 * docs/PLATFORM_CAPABILITIES.md.
 */
class IconShiftPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var registry: AliasRegistry

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        registry = AliasRegistry(context)
        channel = MethodChannel(binding.binaryMessenger, "icon_shift")
        channel.setMethodCallHandler(this)
        recoverLauncherEntry()
    }

    /**
     * Keeps the app launchable after updates: if the enabled alias belongs to
     * a retired variant, or no alias is enabled at all, switch to the
     * replacement (or the default) alias.
     */
    private fun recoverLauncherEntry() {
        try {
            val states = registry.states(registry.aliases())
            val target = AliasSwitchPlanner.recoveryTarget(states, DEFAULT_ID) ?: return
            val plan = AliasSwitchPlanner.plan(states, target)
            if (plan is SwitchPlan.Apply) {
                registry.apply(plan.steps)
                Log.i(TAG, "Recovered the launcher entry: switched to \"$target\".")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Launcher entry recovery failed", e)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "getCapabilities" -> result.success(capabilities())
                "getNativeState" -> result.success(nativeState())
                "setIcon" -> setIcon(call.argument<String>("key"), result)
                "setDisplayName" -> result.error(
                    "unsupported",
                    "Android launcher labels are compiled into activity-aliases. " +
                        "Use setIdentity() with a preconfigured variant.",
                    null,
                )
                "inspect" -> result.success(inspect(call.argument<List<Map<String, Any?>>>("variants").orEmpty()))
                "getApplicationInfo" -> result.success(applicationInfo())
                "loadSelection" -> result.success(SelectionStore(context).load())
                "saveSelection" -> {
                    SelectionStore(context).save(call.argument<Map<String, String>>("selection").orEmpty())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: Exception) {
            result.error("native_failure", e.message ?: e.toString(), null)
        }
    }

    private fun capabilities(): Map<String, Any?> {
        val aliases = registry.aliases()
        val ready = aliases.any { it.variantId == DEFAULT_ID && it.retiredTo == null }
        val limitation = when {
            aliases.isEmpty() -> "No <activity-alias> with meta-data \"icon_shift.variant\" found in " +
                "AndroidManifest.xml. Run icon_shift_generator or add aliases by hand (see README)."
            !ready -> "No activity-alias declares icon_shift.variant=\"default\"; " +
                "IconShift needs it to restore the default identity."
            else -> "Only icons and labels compiled into activity-aliases can be used."
        }
        fun capability() = mapOf(
            "supported" to ready,
            "scope" to if (ready) "launcher" else "none",
            "persistsNatively" to true,
            "requiresPreconfiguredResources" to true,
            "acceptsArbitraryValues" to false,
            "limitation" to limitation,
        )
        return mapOf(
            "icon" to capability(),
            "displayName" to capability(),
            "iconAndNameLinked" to true,
            "notes" to listOf(
                "Launchers cache icons; some take a few seconds or a launcher restart to update.",
                "Home-screen shortcuts pinned to a disabled alias are removed by most launchers.",
            ),
        )
    }

    private fun nativeState(): Map<String, Any?> {
        val aliases = registry.aliases()
        val active = AliasSwitchPlanner.activeVariant(registry.states(aliases))
        return mapOf(
            "iconKey" to active,
            "displayName" to aliases.firstOrNull { it.variantId == active }?.label,
        )
    }

    private fun setIcon(key: String?, result: Result) {
        if (key.isNullOrEmpty()) {
            result.error("invalid_argument", "setIcon needs a variant key.", null)
            return
        }
        val aliases = registry.aliases()
        val label = aliases.firstOrNull { it.variantId == key }?.label
        when (val plan = AliasSwitchPlanner.plan(registry.states(aliases), key)) {
            is SwitchPlan.MissingTarget -> result.error(
                "missing_resource",
                "No <activity-alias> with <meta-data android:name=\"icon_shift.variant\" " +
                    "android:value=\"$key\"/> in AndroidManifest.xml.",
                null,
            )
            is SwitchPlan.Ambiguous -> result.error(
                "missing_resource",
                "Several activity-aliases declare variant \"$key\": ${plan.components.joinToString()}.",
                null,
            )
            SwitchPlan.Unchanged -> result.success(mapOf("status" to "unchanged", "displayName" to label))
            is SwitchPlan.Apply -> {
                registry.apply(plan.steps)
                // Read back instead of assuming success.
                val active = AliasSwitchPlanner.activeVariant(registry.states(registry.aliases()))
                if (active == key) {
                    result.success(mapOf("status" to "applied", "displayName" to label))
                } else {
                    result.error(
                        "native_failure",
                        "PackageManager did not apply the change (active alias: ${active ?: "none or several"}).",
                        null,
                    )
                }
            }
        }
    }

    private fun inspect(variants: List<Map<String, Any?>>): Map<String, Any?> {
        val aliases = registry.aliases()
        val states = registry.states(aliases)
        val issues = mutableListOf<Map<String, Any?>>()
        fun issue(severity: String, code: String, message: String, variantId: String? = null) {
            issues += mapOf("severity" to severity, "code" to code, "message" to message, "variantId" to variantId)
        }

        val configured = variants.mapNotNull { it["id"] as? String }.toSet()
        for (spec in variants) {
            val id = spec["id"] as? String ?: continue
            val matching = aliases.filter { it.variantId == id }
            when {
                matching.isEmpty() -> issue(
                    "error", "missing_alias",
                    "No activity-alias for variant \"$id\". Add one with " +
                        "<meta-data android:name=\"icon_shift.variant\" android:value=\"$id\"/> " +
                        "(icon_shift_generator prints the XML).",
                    id,
                )
                matching.size > 1 -> issue(
                    "error", "duplicate_alias",
                    "Variant \"$id\" is declared by ${matching.size} activity-aliases.", id,
                )
                else -> {
                    val expected = spec["name"] as? String
                    val label = matching.single().label
                    if (expected != null && expected != label) {
                        issue(
                            "warning", "label_mismatch",
                            "The launcher shows the alias label \"$label\" but the configuration " +
                                "says \"$expected\".",
                            id,
                        )
                    }
                }
            }
        }
        aliases.filter { it.variantId !in configured && it.retiredTo == null }.forEach {
            issue(
                "warning", "unconfigured_alias",
                "Activity-alias ${it.component.shortClassName} declares variant \"${it.variantId}\", " +
                    "which is not in the IconShift configuration.",
                null,
            )
        }

        val enabled = states.filter { it.enabled }
        if (aliases.isNotEmpty() && enabled.isEmpty()) {
            issue("error", "no_alias_enabled", "No IconShift activity-alias is enabled; set android:enabled=\"true\" on the default alias.")
        }
        if (enabled.size > 1) {
            issue(
                "warning", "multiple_aliases_enabled",
                "${enabled.size} aliases are enabled (${enabled.joinToString { it.variantId }}); " +
                    "the launcher shows several entries. Only the default alias should have android:enabled=\"true\".",
            )
        }
        val foreign = registry.foreignLauncherEntries(aliases)
        if (aliases.isNotEmpty() && foreign.isNotEmpty()) {
            issue(
                "warning", "duplicate_launcher",
                "${foreign.joinToString()} still declares a MAIN/LAUNCHER intent-filter, so the launcher shows " +
                    "a second entry. Remove that intent-filter; the IconShift aliases provide the launcher entry.",
            )
        }

        return mapOf(
            "issues" to issues,
            "info" to mapOf(
                "sdkInt" to Build.VERSION.SDK_INT,
                "manufacturer" to Build.MANUFACTURER,
                "aliases" to aliases.joinToString { "${it.variantId}=${it.component.shortClassName}" },
                "enabledAliases" to enabled.joinToString { it.variantId },
                "otherLauncherEntries" to foreign.size,
            ),
        )
    }

    private fun applicationInfo(): Map<String, Any?> {
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            pm.getPackageInfo(context.packageName, 0)
        }
        val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        val state = nativeState()
        return mapOf(
            "displayName" to (state["displayName"] as String? ?: context.applicationInfo.loadLabel(pm).toString()),
            "applicationId" to context.packageName,
            "version" to info.versionName,
            "buildNumber" to buildNumber.toString(),
            "installationType" to "standard",
            "osVersion" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        )
    }

    private companion object {
        const val DEFAULT_ID = "default"
        const val TAG = "IconShift"
    }
}

/** Persists the selection requested from Dart. */
internal class SelectionStore(context: Context) {
    private val prefs = context.getSharedPreferences("icon_shift", Context.MODE_PRIVATE)

    fun load(): Map<String, String> =
        prefs.all.mapNotNull { (k, v) -> (v as? String)?.let { k to it } }.toMap()

    fun save(selection: Map<String, String>) {
        prefs.edit().clear().apply { selection.forEach { (k, v) -> putString(k, v) } }.apply()
    }
}
