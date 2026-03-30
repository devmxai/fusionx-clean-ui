# FusionX Clean UI

FusionX Clean UI is a standalone Flutter project that preserves the editor UI
shell from the original FusionX editor while intentionally excluding all media
backend logic.

## Scope

This project contains:

- editor screen layout
- top bar, tools bar, timeline, media dock, and bottom sheet UI
- mock local state used only to present the interface

This project does not contain:

- Rust engine
- preview backend
- playback engine
- export pipeline
- native media player
- platform channels for media control
- networking or persistence layers

## Goal

The purpose of this repository is to keep a clean, reusable UI-only baseline so
the playback/render engine can be rebuilt separately from a fresh foundation.

## Notes

- The preview area is a mock canvas for UI presentation only.
- Timeline and library content are mock data.
- Any play/pause behavior in this project is visual demo behavior only and not
  real media playback.

## Run

```bash
flutter pub get
flutter run
```
