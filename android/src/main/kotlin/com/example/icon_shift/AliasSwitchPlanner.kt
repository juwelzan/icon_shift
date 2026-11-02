package com.example.icon_shift

/** One IconShift activity-alias, reduced to what switching decisions need. */
data class AliasState(
    val componentName: String,
    val variantId: String,
    val enabled: Boolean,
)

/** A component state change: enable or disable [componentName]. */
data class SwitchStep(val componentName: String, val enable: Boolean)

sealed class SwitchPlan {
    /** The target alias is already the only enabled one. */
    object Unchanged : SwitchPlan()

    /** Apply [steps] in order. The target is always enabled first. */
    data class Apply(val steps: List<SwitchStep>) : SwitchPlan()

    /** No alias declares the requested variant. */
    data class MissingTarget(val variantId: String) : SwitchPlan()

    /** Several aliases declare the same variant, so the target is ambiguous. */
    data class Ambiguous(val variantId: String, val components: List<String>) : SwitchPlan()
}

/**
 * Decides which alias components to enable/disable. Pure logic so it can be
 * unit-tested without Android.
 */
object AliasSwitchPlanner {
    fun plan(aliases: List<AliasState>, targetVariant: String): SwitchPlan {
        val targets = aliases.filter { it.variantId == targetVariant }
        if (targets.isEmpty()) return SwitchPlan.MissingTarget(targetVariant)
        if (targets.size > 1) {
            return SwitchPlan.Ambiguous(targetVariant, targets.map { it.componentName })
        }
        val target = targets.single()
        val toDisable = aliases.filter { it !== target && it.enabled }
        if (target.enabled && toDisable.isEmpty()) return SwitchPlan.Unchanged

        // Enable first so the app never has zero launcher entries, even if a
        // later step fails.
        val steps = buildList {
            if (!target.enabled) add(SwitchStep(target.componentName, enable = true))
            toDisable.forEach { add(SwitchStep(it.componentName, enable = false)) }
        }
        return SwitchPlan.Apply(steps)
    }

    /** The variant whose alias is the only enabled one, or null if 0 or >1. */
    fun activeVariant(aliases: List<AliasState>): String? =
        aliases.filter { it.enabled }.singleOrNull()?.variantId
}
