# Nibbler (macOS Apple Silicon)

This repo is a **minimal “packaging repo”** that automatically builds the **latest upstream** [rooklift/nibbler](https://github.com/rooklift/nibbler) as a **macOS `.app` for Apple Silicon (arm64)** and publishes it in **Releases**.

Notes:
- **GUI only** (no `lc0` / Stockfish bundled). You pick an engine path inside Nibbler.
- **Unsigned distribution** (we apply *ad-hoc signing* so macOS doesn’t treat the bundle as “damaged” after modifications).

## Download
Go to the GitHub **Releases** page of this repo and download the `*.zip`, unzip, then open `Nibbler.app` (right click → Open the first time).

## How it works
- GitHub Actions runs on a schedule (and on manual trigger).
- It downloads the **latest upstream Nibbler release tag**.
- It packages it with a pinned Electron version into `Nibbler.app` (arm64).
- It uploads the `.zip` as a Release asset tagged the same as upstream (e.g. `v2.5.2`).

## Build locally
Requirements: macOS, `node` (for `npx`), `curl`, `unzip`.

```bash
./scripts/build.sh
```

Optional overrides:
```bash
NIBBLER_TAG=v2.5.2 ELECTRON_VERSION=40.1.0 ./scripts/build.sh
```
