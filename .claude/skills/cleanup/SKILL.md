---
name: cleanup
description: Clean up project housekeeping tasks (add "run" to execute fixes)
argument-hint: run|check
---

Review the codebase for cleanup tasks:

1. Make sure that the history in @context/current-feature.md is in order from oldest to newest
2. Find `print`/`debugPrint`/`dump` statements in Otter/ and Packages/OtterCore/Sources/ (logging goes through `os.Logger`), and any log line that interpolates note contents
3. Find unused imports
4. Check for stale TODO comments
5. Find orphaned/unused files
6. Check that context files match actual project state
7. Check that Packages/OtterCore/Sources/ does not import AppKit, SwiftUI, or Cocoa
8. Find force unwraps, `try!`, and `as!` without a justifying comment, and `@unchecked Sendable` / `nonisolated(unsafe)` that might be stale

**Mode: $ARGUMENTS**

If no argument or argument is "check":

- Only report findings, don't modify anything
- List what WOULD be cleaned up

If the argument is "run" or "fix":

- First, report all findings with numbered items
- Then ask: "Which items would you like me to fix? (enter numbers like 1,3,5 or 'all' or 'none')"
- Wait for user response before making any changes
- Only fix the items the user specifies
- Report what you changed
