# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS menu bar app (SwiftUI) that monitors Cloudflare Workers and Pages deployment/build history. It lives in the system tray, shows a floating borderless window on click, and sends native notifications when build statuses change.

## Build Commands

```bash
# Build (Release)
xcodebuild -scheme WorkerWidget -configuration Release build

# Build (Debug)
xcodebuild -scheme WorkerWidget -configuration Debug build

# Clean
xcodebuild -scheme WorkerWidget clean
```

SPM dependency: **Sparkle 2.x** for auto-updates (resolved via Xcode SPM integration).

## Architecture

**MVVM + Service singletons**, all UI on `@MainActor`.

### Entry flow
`WorkerWidgetApp` (@main) → `AppDelegate` creates `NSStatusItem` (menu bar icon) + `NSPopover` + `SPUStandardUpdaterController` → click opens/closes the popover with `BuildHistoryView` → settings sheet contains API key, refresh interval, launch-at-login, and check-for-updates.

### Service layer (all `.shared` singletons)
- **CloudflareService** — all Cloudflare API v4 calls (accounts, workers, pages projects, deployments, audit logs). Bearer token auth from Keychain.
- **DataManager** — orchestrates refresh cycle: loads accounts → workers/pages → applies visibility → fetches build history in parallel via `TaskGroup` → caches results → triggers notifications. Owns the periodic auto-refresh timer.
- **CacheManager** — UserDefaults-backed cache for `[BuildStatus]` with per-project staleness tracking and refresh priority (high/medium/low).
- **NotificationManager** — compares new build statuses against last-known state, sends macOS `UNUserNotification` on status changes.
- **KeychainManager** — stores/retrieves the Cloudflare API key in macOS Keychain (`com.workerwidget` service).

### Key models
- **BuildStatus** — unified model for both Worker deployments and Pages builds. Includes `ProjectType` (.worker/.pages) and `BuildStatusType` (.success/.failure/.inProgress/.canceled/.queued). Extensions on `WorkerDeployment` and `PagesDeployment` convert API responses into `BuildStatus`.
- **Worker**, **PagesProject**, **CFAccount** — Cloudflare API response models with visibility toggles.

### Data flow
Cloudflare API → `CloudflareService` → `DataManager` (parallel fetch, merge, sort by date) → `CacheManager` (persist) + `NotificationManager` (diff) → SwiftUI views via `@ObservedObject`/`@StateObject`.

## Important Notes

- The app uses `NSPopover` attached to the menu bar status item — no main window.
- Workers with Builds enabled (GitHub integration) use the Builds API for real build status with commit messages. Workers deployed via wrangler fall back to the deployments API.
- Auto-updates via Sparkle: `SUFeedURL` in Info.plist points to `appcast.xml` in the repo. `SUPublicEDKey` must be set to the EdDSA public key before release. Generate keys with Sparkle's `generate_keys` tool.
