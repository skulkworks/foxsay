# Changelog

## 2.2.2 (2026-09-17, build 16)

### Fixed
- Switching from Nemotron Streaming to a regular speech model could make each new dictation replace the previous one in any app. FoxSay now clears live text tracking between recordings, so completed dictations stay in place without needing to restart the app

## 2.2.1 (2026-09-14, build 15)

### Improved
- The recording overlay keeps its level meter while Nemotron Streaming types. The live transcript used to take the meter's place the moment the first words came back, so the card stopped moving with your voice halfway through a dictation. The meter now stays where it is and the transcript runs on its own line underneath it, with the card growing to fit and shrinking back when the words are gone

## 2.2.0 (2026-09-13, build 14)

### New
- Nemotron Streaming, a speech model that transcribes while you are still talking rather than waiting for you to let go of the key. The words appear in the overlay and go into whatever you are typing in as they are spoken, and releasing the key finishes in a few hundredths of a second because the work is already done. English, about 590 MB, in Speech Models alongside the others. Anything your prompts or dictionary would have rewritten is still rewritten when you let go — FoxSay takes back only the words that changed

### Improved
- The recording overlay now appears when you press the key instead of when the microphone is ready. It used to wait for permission checks, a model check and the audio engine to spin up, which on a warm Mac was about half a second and on a cold or Bluetooth microphone rather longer. It is on screen in about a tenth of a second now, and the fade-in is quicker
- Recording starts roughly three times faster after the first dictation of a session. The audio capture graph is built once and kept rather than assembled from scratch every time you press the key: 240–340ms before, 76–81ms now. The microphone is still released between dictations, so the orange recording dot behaves exactly as it did, and the graph is given back after a minute of not dictating
- Pressing the hotkey during the model preload at launch no longer waits for the preload to finish. FoxSay checked with the speech model whether it was ready, and that question had to queue behind the model loading itself — up to fifteen seconds on a cold start

## 2.1.1 (2026-08-26, build 13)

### New
- Stop button on a model download, for a download that is going nowhere or a model you picked by mistake. What has already been fetched is kept, so starting again carries on from there rather than going back to the beginning
- Unused model files row in Speech Models, offering to remove the copy an earlier version of FoxSay downloaded into a folder this version no longer reads. It shows how much that copy is taking up, and only ever removes that older copy

### Improved
- A model download says "Preparing…" while it works out what to fetch, instead of sitting at 0% for the several seconds that takes
- Debug builds are now a separate app, `FoxSay (DEV)`, with their own bundle identifier. macOS ties privacy permissions to the identifier and code signature, so a debug build sharing the released app's identifier had Microphone and Accessibility revoked on every rebuild, and granting them took them away from the released copy. Each now has its own entries, granted once. Models, history and statistics stay shared; settings do not. Automatic update checks are off in debug builds, so the dev build cannot install the released version over itself

### Fixed
- Download progress reaching 80% within seconds and then sitting there for the rest of the download, however long that took. Speech models and AI models both report the real fraction fetched now, straight from the download, so the bar tracks the bytes arriving and reaches 100% when the model is ready
- Updating from FoxSay 1.x reporting an already-downloaded speech model as missing and fetching the whole thing again. The folder these models are kept in was renamed between the two versions, so the model was still on the disk, just not where FoxSay had started looking. A Parakeet V2 model downloaded by 1.x is now picked up where it lies. Parakeet V3's files changed at the same time and cannot be reused, so that one still needs downloading again
- Accuracy card on the dashboard sitting lower than the other three statistics, because it had no trend line to fill the row
- Status in the sidebar footer not being clickable — it reports permission and model problems, so it now jumps to System Status on the dashboard, where those are fixed

## 2.1.0 (2026-08-24, build 12)

### New
- Spoken Punctuation toggle in General settings: say "comma", "question mark", "quote … unquote", "open parentheses … close parentheses", "dash", "dash dash" for an em dash, or "new paragraph" and get the marks instead of the words. A spoken mark replaces the punctuation the speech model added for the same pause, rather than stacking on top of it, and bracket pairs open or close based on what is already open rather than on hearing the words "open" and "close"

### Fixed
- Commas being stripped out of every transcription, so "testing, one, two, three." came through as "testing one two three."

## 2.0.0 (2026-07-28, build 11)

### New
- About pane in the main window, with the version, links and the update check
- Our Apps pane listing the rest of the SkulkWorks apps
- Vocal Corrections toggle in General settings
- Parakeet TDT-CTC 110M speech model (English only, the smallest and fastest Parakeet)
- Parakeet Japanese 0.6B speech model, more accurate for Japanese than the multilingual V3
- Current-generation local AI models: Qwen 3.5 2B, Qwen 3 4B Instruct 2507, Qwen 3 1.7B, Gemma 3 1B QAT, Gemma 4 E2B, LFM2 1.2B and Llama 3.2 1B

### Improved
- New app icon, and a redesign of the whole app around it: one coral accent, neutral surfaces and consistent cards throughout
- Recording overlay rebuilt as three studio meters (LED Meter, Analyzer and Waveform) with much faster level metering
- About opens in the main window instead of a separate panel
- Check for Updates moved from the app menu into the About pane
- Qwen 2.5 1.5B is now the recommended AI model, with a rewritten vocal-corrections prompt

### Fixed
- Recording overlay shadow clipping into a hard square ring on bright desktops
- Overlay corner radius not matching the system window radius
- Prompt selector insets sitting unevenly against the overlay corners
- Reasoning tags leaking into transcribed text when using a remote AI provider
- Parakeet models failing to load with FluidAudio 0.15.x
- Clean checkouts of the repository failing to build, from sources hidden by an over-broad .gitignore and unpinned dependencies

## 1.0.9 (2026-02-20, build 10)

### Improved
- Smoother audio visualization animations in recording overlay

### Fixed
- Recording overlay not appearing after disconnecting external monitors (saved position was off-screen)

## 1.0.8 (2026-02-17, build 9)

### Improved
- All error states now show descriptive overlay messages that auto-dismiss after 3 seconds
- Speech model availability is verified from disk before each recording session
- Overlay error display is now dynamic, supporting different icons and messages per error type

### Fixed
- App silently failing when a speech model's files are deleted from disk
- Overlay getting stuck when no audio is captured (quick press-release)
- No visible feedback when microphone permission is denied
- No visible feedback when recording or transcription fails unexpectedly

## 1.0.7 (2026-02-06, build 8)

### Fixed
- Crash when using dictation hotkey on a Mac with no microphone connected
- Added friendly overlay error message when no microphone is detected, with auto-dismiss

## 1.0.6 (2026-02-03, build 7)

### New
- Ability to assign remote AI models to specific apps
- New presets for remote AI models: OpenAI, Anthropic, Google, OpenRouter
- Discord community link

### Fixed
- Various bug fixes and UI improvements

## 1.0.5 (2026-02-02, build 6)

### New
- Download badge for README

### Fixed
- Menu bar only mode not working correctly

## 1.0.4 (2026-02-02, build 5)

### New
- Audio visualization styles: scrolling, spectrum, and pulsing
- Activity stats with 1-year scaling

### Improved
- Removed 30-day activity limitation

### Fixed
- Various UI and stability fixes

## 1.0.3 (2026-02-02, build 4)

### New
- Stats and dashboard view
- Screenshot for documentation

### Fixed
- UI fixes and improvements

## 1.0.2 (2026-02-01, build 3)

### New
- Auto-update support via Sparkle framework
- Appcast for update distribution

## 1.0.1 (2026-02-01, build 2)

### Improved
- Updated build script

## 1.0.0 (2026-02-01, build 1)

### New
- Initial public release
- On-device speech-to-text transcription using Parakeet (FluidAudio) and Whisper (WhisperKit)
- Hold-to-talk hotkey with configurable modifier keys
- Multiple activation modes: hold, toggle, double-tap, and hold-or-toggle
- LLM-powered corrections using local AI models (Qwen, Gemma, Llama, Phi, Mistral) via Apple MLX
- Support for remote OpenAI-compatible LLMs
- Configurable system prompts for AI corrections
- Markdown voice mode for dictating formatted text
- Model preloading for faster first transcription
- Transcription history with delete functionality
- Interface sound options for overlay open/close
- Input overlay with smooth animations
- Sidebar with collapsible sections
- Blank transcription detection to abort pipeline early
- Apache 2.0 license

### Improved
- Renamed project from VoiceFox to FoxSay
- Refactored AI system to support custom local models and prompts
- Improved selector overlay UI
- Color and icon updates throughout the app
- Markdown mode moved to experimental

### Fixed
- Punctuation handling improvements
- Removed sandboxing requirements for better accessibility
