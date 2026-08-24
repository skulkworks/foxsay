# Changelog

## 2.1.1 (2026-08-24, build 13)

### Fixed
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
