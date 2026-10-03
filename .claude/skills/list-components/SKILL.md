---
name: list-components
description: List project components
argument-hint: subdirectory
---

## Task

List all Swift source files (.swift) in `Otter/` (app target) and `Packages/OtterCore/Sources/OtterCore/` (core package).

If a [subdirectory] is provided via $ARGUMENTS (e.g. `Panel`, `Destinations/Obsidian`), only list files in that subdirectory of either module.

## Output Format

- Group by module (Otter app, OtterCore), then by folder
- Numbered list of files with relative paths
- Brief one-line description of each (infer from the filename and its primary type)
- Summary count at the end

If no files found, say "No components found."
