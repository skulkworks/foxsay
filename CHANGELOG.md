# Changelog

All notable changes to FoxSay will be documented in this file.

## [1.0.7] - 2026-02-06

### Fixed
- Crash when using dictation hotkey on a Mac with no microphone connected
- Added friendly overlay error message when no microphone is detected, with auto-dismiss

## [1.0.6] - 2026-02-03

### Added
- Ability to assign remote AI models to specific apps
- New presets for remote AI models: OpenAI, Anthropic, Google, OpenRouter
- Discord community link

### Fixed
- Various bug fixes and UI improvements

## [1.0.5] - 2026-02-02

### Added
- Download badge for README

### Fixed
- Menu bar only mode not working correctly

## [1.0.4] - 2026-02-02

### Added
- Audio visualization styles: scrolling, spectrum, and pulsing
- Activity stats with 1-year scaling

### Changed
- Removed 30-day activity limitation

### Fixed
- Various UI and stability fixes

## [1.0.3] - 2026-02-02

### Added
- Stats and dashboard view
- Screenshot for documentation

### Fixed
- UI fixes and improvements

## [1.0.2] - 2026-02-01

### Added
- Auto-update support via Sparkle framework
- Appcast for update distribution

## [1.0.1] - 2026-02-01

### Changed
- Updated build script

## [1.0.0] - 2026-02-01

Initial public release.

### Added
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

### Changed
- Renamed project from VoiceFox to FoxSay
- Refactored AI system to support custom local models and prompts
- Improved selector overlay UI
- Color and icon updates throughout the app
- Markdown mode moved to experimental

### Fixed
- Punctuation handling improvements
- Removed sandboxing requirements for better accessibility
