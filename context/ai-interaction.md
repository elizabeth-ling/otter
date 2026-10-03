# AI Interaction Guidelines

## Communication

- Be concise and direct; explain non-obvious decisions briefly
- Ask before large refactors or architectural changes
- Never delete files without clarification

## Workflow

Common workflow for every feature/fix:

1. **Document** - Capture the feature in @context/current-feature.md
2. **Branch** - Create a branch named `feature/[name]` or `fix/[name]`
3. **Implement** - Build it per @context/current-feature.md
4. **Test** - Run `swift test` in `Packages/OtterCore` and `xcodebuild -scheme Otter build`; fix any errors. UI behavior is tested by hand in the running app
5. **Iterate** - Adjust as needed
6. **Commit** - Only after the build passes and with permission (see Commits)
7. **Merge** - Merge to main, then delete the branch (ask first)
8. **Record** - Mark completed in @context/current-feature.md and add to history

## Commits

- Never commit without permission or before the build and tests pass
- Conventional messages (feat:, fix:, chore:, etc.), one feature/fix per commit
- Never put "Generated With Claude" in commit messages

## Code Changes

- Make the minimal change to accomplish the task
- Don't refactor unrelated code or add features beyond the spec unless asked
- Preserve existing patterns in the codebase

## When Stuck

- If something isn't working after 2-3 attempts, stop and explain the issue — don't try random fixes
- Ask for clarification if requirements are unclear

## Code Review

Review AI-generated code periodically and on demand, especially for:

- Security (user content passed to `osascript` only as argv, file paths and names sanitized, no note contents in logs)
- Performance (nothing slow on the hotkey → panel path or the main thread, no idle timers)
- Logic errors (edge cases)
- Patterns (matches existing codebase?)
