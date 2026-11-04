package com.example.icon_shift

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
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
 *
 * The launcher label belongs to the alias, so it only changes with the
 * variant. The recent-apps (task) label is set at runtime: it follows the
 * active alias, or an arbitrary name from setDisplayName.
 */
class IconShiftPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var registry: AliasRegistry
    private var activity: Activity? = null

    /** Name from setDisplayName; null shows the active alias label. */
    private var customLabel: String? = null

    /** Activities of this app that are started (visible). */
    private var startedActivities = 0

    /**
     * Applies a deferred launcher switch once the app has left the
     * foreground. Disabling the component the visible screen was opened
     * through makes Android finish that task ("disabled-package"), so the
     * switch waits until nothing is on screen.
     */
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(a: Activity) {
            startedActivities++
        }

        override fun onActivityStopped(a: Activity) {
            startedActivities = maxOf(0, startedActivities - 1)
            if (startedActivities == 0 && !a.isChangingConfigurations) applyPendingSwitch()
        }

        override fun onActivityCreated(a: Activity, state: Bundle?) {}
        override fun onActivityResumed(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        registry = AliasRegistry(context)
        channel = MethodChannel(binding.binaryMessenger, "icon_shift")
        channel.setMethodCallHandler(this)
        (context as? Application)?.registerActivityLifecycleCallbacks(lifecycle)
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
        (context as? Application)?.unregisterActivityLifecycleCallbacks(lifecycle)
    }

    private val pendingStore get() =
        context.getSharedPreferences("icon_shift_native", Context.MODE_PRIVATE)

    /** Variant whose alias is waiting to be enabled, if any. */
    private var pendingSwitch: String?
        get() = pendingStore.getString("pending_variant", null)
        set(value) {
            pendingStore.edit().apply {
                if (value == null) remove("pending_variant") else putString("pending_variant", value)
            }.apply()
        }

    /** The switch would disable the component the visible screen came from. */
    private fun closesVisibleScreen(steps: List<SwitchStep>): Boolean {
        if (startedActivities == 0) return false
        val opened = activity?.componentName?.className ?: return false
        return steps.any { !it.enable && it.componentName == opened }
    }

    private fun applyPendingSwitch() {
        val key = pendingSwitch ?: return
        pendingSwitch = null
        try {
            val plan = AliasSwitchPlanner.plan(registry.states(registry.aliases()), key)
            if (plan is SwitchPlan.Apply) {
                registry.apply(plan.steps)
                Log.i(TAG, "Applied the deferred launcher switch to \"$key\".")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Deferred launcher switch to \"$key\" failed", e)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (customLabel != null) applyTaskLabel()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    /** The label of the active alias, or null when none is active. */
    private fun activeAliasLabel(): String? {
        val aliases = registry.aliases()
        val active = AliasSwitchPlanner.activeVariant(registry.states(aliases))
        return aliases.firstOrNull { it.variantId == active }?.label
    }

    /**
     * Shows [customLabel] (or the active alias label) in the recent-apps
     * screen. A running task keeps the label of the alias it was launched
     * from until it is set here. Returns false without an activity.
     */
    private fun applyTaskLabel(): Boolean {
        val target = activity ?: return false
        val label = customLabel ?: activeAliasLabel() ?: return true
        @Suppress("DEPRECATION")
        val description = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityManager.TaskDescription.Builder().setLabel(label).build()
        } else {
            ActivityManager.TaskDescription(label)
        }
        target.runOnUiThread { target.setTaskDescription(description) }
        return true
    }

    private fun setDisplayName(name: String?, result: Result) {
        if (name != null && name.isBlank()) {
            result.error("invalid_argument", "The display name must not be blank.", null)
            return
        }
        val current = customLabel ?: activeAliasLabel()
        customLabel = name
        val target = name ?: activeAliasLabel()
        when {
            !applyTaskLabel() -> result.success(
                mapOf(
                    "status" to "pending",
                    "message" to "No activity yet; the recent-apps label is set when it starts.",
                ),
            )
            target == current -> result.success(mapOf("status" to "unchanged"))
            else -> result.success(
                mapOf(
                    "status" to "applied",
                    "message" to "Shown in the recent-apps screen. The launcher label only changes " +
                        "with setIdentity() (activity-alias labels are compiled into the app).",
                ),
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "getCapabilities" -> result.success(capabilities())
                "getNativeState" -> result.success(nativeState())
                "setIcon" -> setIcon(
                    call.argument<String>("key"),
                    call.argument<Boolean>("immediate") ?: false,
                    result,
                )
                "setDisplayName" -> setDisplayName(call.argument<String>("name"), result)
                "inspect" -> result.success(inspect(call.argument<List<Map<String, Any?>>>("variants").orEmpty()))
                "getApplicationInfo" -> result.success(applicationInfo())
                "getLauncherIdentities" -> result.success(launcherIdentities())
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
            "displayName" to mapOf(
                "supported" to true,
                "scope" to "taskSwitcher",
                "persistsNatively" to false,
                "requiresPreconfiguredResources" to false,
                "acceptsArbitraryValues" to true,
                "limitation" to "Any name is shown in the recent-apps screen. The launcher label changes " +
                    "only with setIdentity(), to the label compiled into the variant's activity-alias.",
            ),
            "iconAndNameLinked" to true,
            "notes" to listOf(
                "Launchers cache icons; some take a few seconds or a launcher restart to update.",
                "Home-screen shortcuts pinned to a disabled alias are removed by most launchers.",
                "MaterialApp.title also sets the recent-apps label on every rebuild; bind it to " +
                    "IconShift.displayNameListenable so it does not undo a change.",
            ),
        )
    }

    /**
     * The launcher identities compiled into this APK, as PackageManager
     * reports them: one per IconShift activity-alias (retired ones are left
     * out), with its label and whether it is the enabled launcher entry.
     * These are the only names the launcher entry can show without a new
     * build.
     */
    private fun launcherIdentities(): List<Map<String, Any?>> {
        val aliases = registry.aliases().filter { it.retiredTo == null }
        val states = registry.states(aliases).associateBy { it.componentName }
        return aliases.map {
            mapOf(
                "id" to it.variantId,
                "label" to it.label,
                "component" to it.component.className,
                "enabled" to (states[it.component.className]?.enabled == true),
            )
        }
    }

    private fun nativeState(): Map<String, Any?> {
        val aliases = registry.aliases()
        val active = AliasSwitchPlanner.activeVariant(registry.states(aliases))
        return mapOf(
            "iconKey" to active,
            "pendingIconKey" to pendingSwitch,
            "displayName" to (customLabel ?: aliases.firstOrNull { it.variantId == active }?.label),
        )
    }

    private fun setIcon(key: String?, immediate: Boolean, result: Result) {
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
            SwitchPlan.Unchanged -> {
                // Asking for what is already active cancels a deferred switch.
                pendingSwitch = null
                // Switching to the active variant still drops a custom name.
                customLabel = null
                applyTaskLabel()
                result.success(mapOf("status" to "unchanged", "displayName" to label))
            }
            is SwitchPlan.Apply -> {
                if (!immediate && closesVisibleScreen(plan.steps)) {
                    pendingSwitch = key
                    result.success(
                        mapOf(
                            "status" to "pending",
                            "displayName" to label,
                            "message" to "Switches when the app leaves the foreground: disabling the " +
                                "launcher entry this screen was opened from would make Android close it.",
                        ),
                    )
                    return
                }
                pendingSwitch = null
                registry.apply(plan.steps)
                // Read back instead of assuming success.
                val active = AliasSwitchPlanner.activeVariant(registry.states(registry.aliases()))
                if (active == key) {
                    // The running task still shows the old alias label.
                    customLabel = null
                    applyTaskLabel()
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
        return mapOf(
            "displayName" to (activeAliasLabel() ?: context.applicationInfo.loadLabel(pm).toString()),
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
