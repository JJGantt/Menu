# Menu — iOS + watchOS Reference App

SwiftUI iPhone and Apple Watch app for a restaurant's menu (food, wines, liquor, cocktails), with an
assistant that answers questions about it and edits the bar's restock list, plus owner-only voice order
taking on the watch. The code holds no restaurant data: all of it is read from Supabase. `CLAUDE.md` is
the full reference: architecture, data model, release process.

## Setup

1. Copy `MenuApp/Secrets.swift.example` to `MenuApp/Secrets.swift` and paste an
   Anthropic API key and the Supabase publishable key. `Secrets.swift` is gitignored. The Anthropic key
   is only read by debug builds; release builds take it from Settings on the phone, which syncs it to
   the watch.
2. `xcodegen generate` (the project is generated from `project.yml`).
3. Ship to devices with `./scripts/release.sh` (TestFlight). See `CLAUDE.md`.

## Assistant

Questions go straight to the Anthropic API from the device (Haiku, Sonnet or Opus, limited per device
by `AppGate`). The watch records audio and transcribes it through the status hub's `/api/cg/transcribe`.

## Data

- The menu, dish photos, bottles, cocktails, restock list, prompt rules and the restaurant's name live
  in Supabase (project `life-data`); schema is in data-layer's migrations.
- The app keeps the last copy it fetched on the device, and `scripts/seed.sh` bundles a copy at build
  time (`Seed/`, gitignored) for a fresh install's first launch.
