# 0005. XcodeGen for project generation

- **Status:** Accepted
- **Date:** 2026-10-21

## Context
`.xcodeproj/project.pbxproj` is a large, opaque file that is hard to review, merge-conflict prone, and error-prone for an AI agent to edit.

## Decision
Define targets, settings, packages, and schemes in a human-readable `project.yml` and generate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `*.xcodeproj` is gitignored.

## Consequences
- Project changes are small, reviewable YAML diffs; adding files needs no project edits (folders are globbed).
- Everyone (and every agent) must run `xcodegen generate` after pulling or changing `project.yml`.
- Settings edited in Xcode's UI are lost on regeneration — always change `project.yml` instead.
