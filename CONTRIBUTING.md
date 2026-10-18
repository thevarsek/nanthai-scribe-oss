# Contributing to Scribe

The public repository contains the Mac app, shared code, Mac tools, and website.
The iPhone app and keyboard remain closed source. Public changes are integrated
into private development and return through the curated sync.

Open an issue or pull request at
[thevarsek/nanthai-scribe-oss](https://github.com/thevarsek/nanthai-scribe-oss).
Describe the problem, the change, and how you checked it. Small, focused changes
are easier to review. No contributor agreement or extra sign-off is required.

## Layout

- `Sources/ScribeCore`: shared dictation, models, rewriting, and persistence.
- `Sources/ScribeUI`: shared design tokens and views.
- `Sources/ScribeMacCore`: Mac flow logic.
- `Sources/ScribeMac`: menu bar app and Mac integrations.
- `Tests`: matching Mac and shared test targets.
- `Resources`, `Makefile`, and `Tools/release`: app packaging.
- `website`: Astro website and help pages.

Use Swift 6 language mode with strict concurrency. Keep shared code free of
Mac-only assumptions. Follow [docs/DESIGN.md](docs/DESIGN.md) for interface work.
Preserve on-device processing and avoid logging transcripts.

## Checks

Use an Apple silicon Mac with macOS 26, Xcode 26.6+, Swift 6.3+, and the Metal
toolchain. See [README.md](README.md) for signing with `Config.local.mk`.

```sh
swift build
swift test --no-parallel -j 4
make app
```

`make app` leaves a bundle in `build/`. Test that bundle without replacing an
installed app. Use synthetic audio for repeatable speech checks. Optional model
downloads are explicit; the tests do not need to download model weights.

For website changes, run `npm ci` and `npm run build` inside `website/`.

Contributions to exported code use the project's Apache-2.0 licence. Third-party
material keeps its own licence; add attribution when introducing it.
