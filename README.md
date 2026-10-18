# NanthAi Scribe

Scribe is on-device dictation for Mac. Hold a key, speak, and release to put text
in the focused app. It also records meetings and transcribes audio files.

The iPhone app and keyboard are distributed through the App Store and remain
closed source. The Mac app, shared code, Mac tools, and website are open source.
See [scribe.nanthai.tech](https://scribe.nanthai.tech) for downloads and guides.

## Features

- Push-to-talk and hands-free dictation with a configurable shortcut.
- Polish, translate, and edit selected text with on-device models.
- Dictionary replacements, snippets, and styles for individual apps.
- Local history, a note library, and meeting transcription with speaker labels.
- Apple speech recognition and an optional Parakeet language pack.

## Privacy

Audio and text are processed on your device. Scribe has no analytics or telemetry.
Optional models download from Hugging Face when you request them. Apple manages
its own speech and Apple Intelligence assets. Update checks contact the website;
automatic checks are off by default and can be enabled in Settings.

## Build from source

Use an Apple silicon Mac with macOS 26 or later, Xcode 26.6 or later, and Swift 6.3
or later. Install the Xcode Metal toolchain for MLX shader compilation. SwiftPM
fetches the dependencies pinned in `Package.resolved` on the first build.

```sh
swift build
swift test --no-parallel -j 4
make app
open 'build/NanthAi Scribe.app'
```

`make app` creates a local bundle. It does not replace an installed copy. Grant
Microphone and Accessibility access to use dictation and paste into other apps.
Meeting system audio uses macOS audio capture permission.

Signing settings can come from the environment, make arguments, or an ignored file:

```sh
cp Config.local.mk.example Config.local.mk
# Edit Config.local.mk to set SIGN_ID, TEAM_ID, and optionally NOTARY_PROFILE.
make app
```

Without an explicit identity, the build detects a Developer ID or signs ad-hoc.
A stable signing identity keeps Accessibility grants across rebuilds. `TEAM_ID`
filters automatic identity detection. `NOTARY_PROFILE` names a local Keychain
profile; it is used only by `make dmg`. See [Mac release tools](Tools/release/README.md)
for packaging, notarization, and Sparkle setup.

## Models and licences

Model weights are downloaded separately. They are not included in this repository
or the app bundle. Library licences do not replace model licences.

| Component | Licence / terms |
| --- | --- |
| Apple Speech and Foundation Models | Apple system frameworks and assets, under Apple's SDK and software terms. Availability depends on the Mac and language. |
| NVIDIA Parakeet TDT 0.6B v3 | [CC BY 4.0](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3); [Core ML conversion by FluidInference](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). |
| Google Gemma 4 E2B QAT | [Gemma 4 licence: Apache 2.0](https://ai.google.dev/gemma/docs/gemma_4_license). Scribe uses the [MLX QAT 4-bit conversion](https://huggingface.co/mlx-community/gemma-4-E2B-it-qat-4bit). |
| Meeting speaker models | [FluidInference conversion](https://huggingface.co/FluidInference/speaker-diarization-coreml): pyannote segmentation 3.0 (MIT) and WeSpeaker embedding (CC BY 4.0). |
| FluidAudio 0.17.7 | [Apache 2.0](https://github.com/FluidInference/FluidAudio/blob/0.17.7/LICENSE). |
| mlx-swift-lm 3.32.3 and mlx-swift 0.32.3 | [MIT](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/LICENSE). |
| swift-transformers 1.3.5 | [Apache 2.0](https://github.com/huggingface/swift-transformers/blob/1.3.5/LICENSE). |
| Sparkle 2.9.6 | [Sparkle licence and bundled component notices](https://github.com/sparkle-project/Sparkle/blob/2.9.6/LICENSE). |

Versions above match `Package.resolved`. Model catalogues pin revisions and checksums
in `Sources/ScribeCore/Models/Catalog/`. [NOTICE](NOTICE) includes dependency,
model, website font, and build-tool credits.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout and checks, and
[docs/DESIGN.md](docs/DESIGN.md) for the interface specification.
Report security issues to [support@nanthai.tech](mailto:support@nanthai.tech);
see [SECURITY.md](SECURITY.md).

## Licence

Copyright 2026 NanthAI. The exported Mac app, shared code, Mac tools, and website
are licensed under [Apache 2.0](LICENSE), except third-party material under its
own terms. The iPhone app and keyboard remain closed source.

## Repository model

This repository is a curated export of private development. It contains the Mac
app and shared code, their tests, Mac build tools, and website. The iPhone app,
keyboard decoder, lexicons, internal plans, and private history are excluded.
The public `Package.swift` builds only Mac and shared targets.
