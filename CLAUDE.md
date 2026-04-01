# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS menu bar app (SwiftUI) that monitors Cloudflare Workers and Pages deployment/build history. It lives in the system tray, shows a floating borderless window on click, and sends native notifications when build statuses change.

## Build Commands

```bash
# Build (Release)
xcodebuild -scheme WorkerBuildHistory -configuration Release build

# Build (Debug)
xcodebuild -scheme WorkerBuildHistory -configuration Debug build

# Clean
xcodebuild -scheme WorkerBuildHistory clean
```

No test suite, linter, or package manager (SPM/CocoaPods) is configured — all dependencies are Apple system frameworks.

## Architecture

**MVVM + Service singletons**, all UI on `@MainActor`.

### Entry flow
`WorkerBuildHistoryApp` (@main) → `AppDelegate` creates `NSStatusItem` (menu bar icon) → click opens/closes a floating `NSWindow` hosting `BuildHistoryView` → settings sheet contains API key input and worker/pages visibility toggles.

### Service layer (all `.shared` singletons)
- **CloudflareService** — all Cloudflare API v4 calls (accounts, workers, pages projects, deployments, audit logs). Bearer token auth from Keychain.
- **DataManager** — orchestrates refresh cycle: loads accounts → workers/pages → applies visibility → fetches build history in parallel via `TaskGroup` → caches results → triggers notifications. Owns the periodic auto-refresh timer.
- **CacheManager** — UserDefaults-backed cache for `[BuildStatus]` with per-project staleness tracking and refresh priority (high/medium/low).
- **NotificationManager** — compares new build statuses against last-known state, sends macOS `UNUserNotification` on status changes.
- **KeychainManager** — stores/retrieves the Cloudflare API key in macOS Keychain (`com.workerbuildhistory` service).

### Key models
- **BuildStatus** — unified model for both Worker deployments and Pages builds. Includes `ProjectType` (.worker/.pages) and `BuildStatusType` (.success/.failure/.inProgress/.canceled/.queued). Extensions on `WorkerDeployment` and `PagesDeployment` convert API responses into `BuildStatus`.
- **Worker**, **PagesProject**, **CFAccount** — Cloudflare API response models with visibility toggles.

### Data flow
Cloudflare API → `CloudflareService` → `DataManager` (parallel fetch, merge, sort by date) → `CacheManager` (persist) + `NotificationManager` (diff) → SwiftUI views via `@ObservedObject`/`@StateObject`.

## Important Notes

- The app has no main window — it's a menu bar app using `Settings` scene as a workaround. The primary UI is the floating `NSWindow` created in `AppDelegate`.
- Worker deployments don't have a direct "build" status — the app infers build state from deployment strategy, version percentages, audit logs, and timing heuristics.
- The Cloudflare Workers Builds API endpoint is private/unavailable, so the app relies on deployments + audit log correlation as a workaround.
- Git history contains an exposed API key (noted in readme.md) — must be rotated before making the repo public.
