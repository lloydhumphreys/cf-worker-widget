# WorkerWidget

A macOS menu bar app that monitors your Cloudflare Workers and Pages build/deployment history.

Click the cloud icon in your menu bar to see the latest status of all your projects at a glance. Click into any project to see recent builds with commit messages, branches, and build times. Click a build to open it in the Cloudflare dashboard.

## Features

- Live build status for Cloudflare Workers (via Builds API) and Pages projects
- Click-to-open builds in the Cloudflare dashboard
- Native macOS notifications on build failures
- Auto-updates via Sparkle

## Setup

1. Build and run from Xcode (`WorkerWidget.xcodeproj`)
2. Click the cloud icon in your menu bar
3. Open Settings and add your Cloudflare API token

Your API token needs these permissions:
- **Workers Scripts**: Read
- **Workers Builds Configuration**: Read (for Workers with Builds/GitHub integration)
- **Pages**: Read

The token is stored in your macOS Keychain.

## Disclaimer

Not affiliated with Cloudflare. We just really like them.

## License

MIT
