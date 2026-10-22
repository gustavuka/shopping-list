# 0001. Native SwiftUI, iOS 26 minimum

- **Status:** Accepted
- **Date:** 2026-10-21

## Context
The app is for two people with up-to-date iPhones. The top priorities are snappiness, fluid motion, and great visuals. Cross-platform frameworks (React Native, Flutter) add a runtime layer and lag behind the native look, especially iOS 26's Liquid Glass.

## Decision
Build a native SwiftUI app targeting **iOS 26.0+**, Swift 6 language mode. Use Liquid Glass, the `@Observable` macro, SwiftData, and modern SwiftUI APIs without availability checks.

## Consequences
- Best possible performance, animation quality, and system integration (haptics, widgets, App Intents later).
- No `if #available` branching — simpler code.
- iPhones that can't run iOS 26 are unsupported; acceptable for two known users.
- No Android/web client from this codebase.
