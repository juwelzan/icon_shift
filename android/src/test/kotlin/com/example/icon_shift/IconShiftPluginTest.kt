package com.example.icon_shift

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/*
 * Unit tests of the alias switching logic. Run with
 * `./gradlew :icon_shift:testDebugUnitTest` from example/android.
 * Behaviour against a real PackageManager is covered by the example app's
 * integration test.
 */
internal class AliasSwitchPlannerTest {
    private val default = AliasState(".IconShiftAlias_default", "default", enabled = true)
    private val dark = AliasState(".IconShiftAlias_dark", "dark", enabled = false)
    private val blue = AliasState(".IconShiftAlias_blue", "blue", enabled = false)

    @Test
    fun enablesTargetBeforeDisablingCurrent() {
        val plan = AliasSwitchPlanner.plan(listOf(default, dark, blue), "dark")
        assertEquals(
            SwitchPlan.Apply(
                listOf(
                    SwitchStep(".IconShiftAlias_dark", enable = true),
                    SwitchStep(".IconShiftAlias_default", enable = false),
                ),
            ),
            plan,
        )
    }

    @Test
    fun unchangedWhenTargetIsTheOnlyEnabledAlias() {
        assertEquals(SwitchPlan.Unchanged, AliasSwitchPlanner.plan(listOf(default, dark), "default"))
    }

    @Test
    fun repairsSeveralEnabledAliases() {
        val plan = AliasSwitchPlanner.plan(listOf(default, dark.copy(enabled = true), blue), "default")
        assertEquals(SwitchPlan.Apply(listOf(SwitchStep(".IconShiftAlias_dark", enable = false))), plan)
    }

    @Test
    fun repairsNoEnabledAlias() {
        val plan = AliasSwitchPlanner.plan(listOf(default.copy(enabled = false), dark), "dark")
        assertEquals(SwitchPlan.Apply(listOf(SwitchStep(".IconShiftAlias_dark", enable = true))), plan)
    }

    @Test
    fun missingAndAmbiguousTargets() {
        assertEquals(SwitchPlan.MissingTarget("red"), AliasSwitchPlanner.plan(listOf(default), "red"))
        val twin = AliasState(".Other", "dark", enabled = false)
        assertEquals(
            SwitchPlan.Ambiguous("dark", listOf(".IconShiftAlias_dark", ".Other")),
            AliasSwitchPlanner.plan(listOf(default, dark, twin), "dark"),
        )
    }

    @Test
    fun activeVariantNeedsExactlyOneEnabledAlias() {
        assertEquals("default", AliasSwitchPlanner.activeVariant(listOf(default, dark)))
        assertNull(AliasSwitchPlanner.activeVariant(listOf(default, dark.copy(enabled = true))))
        assertNull(AliasSwitchPlanner.activeVariant(listOf(default.copy(enabled = false))))
    }
}
