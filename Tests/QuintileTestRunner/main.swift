// Quintile test runner — see TestHarness.swift for why this is an executable.
// Register each unit's test entry point here.

let harness = TestHarness()

gridMathTests(harness)
displayStoreTests(harness)
permissionTests(harness)
hotkeyTests(harness)

harness.finish()
