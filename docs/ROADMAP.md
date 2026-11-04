# Cicada roadmap

English · [简体中文](ROADMAP.zh-CN.md)

In rough order, and subject to change. Tell us what you need in Issues.

**Next (Mac)**
- **Recording what you say.** Cicada only hears what your Mac plays, so what you say into the meeting isn't captured; only the lines you speak while holding the talk key are recorded as "you". A switch will let it listen to your microphone throughout the meeting, so your proposals and the to-dos you take on make it into the transcript and notes. Without headphones, echo cancellation keeps the other side's voice from being recorded twice. While it's on, the microphone indicator in the menu bar stays lit.
- **Developer ID signing and notarization.** Removes the "Open Anyway" prompt on first launch and stores the AI key in the macOS Keychain.
- **Speaker recognition.** Speaker identification (experimental, since 1.0) already tells the other side's voices apart within a meeting, lets you rename them and names to-do owners, but forgets them when the meeting ends. Next, Cicada will remember frequent meeting participants by voice so they're named in the next meeting too. Because voiceprints are biometric data, they stay on your Mac, require opt-in, and can be deleted anytime.
- **Local notes without an API key.** Use Apple's on-device model to generate meeting notes on supported Macs, keeping all audio and text local.

**Later**
- **Live voice changing.** No translation: your voice goes into the meeting as a different voice, changed as you speak, without holding the talk key. Setting "I speak" and "They hear" to the same language already swaps the voice today, but it goes through text, so the room hears it only after you let go and your tone is lost.
- **Windows.** Per-process audio capture is available on Windows 10 2004+, so the recognition, translation and notes pipeline carries over with a Windows virtual audio driver. This will be a separate codebase sharing the same notes and meeting-record formats.
- **Android.** Can listen to videos and livestreams (capturing audio from other apps works on Android 10+), but Android blocks capturing phone and meeting call audio, and translated speech cannot be injected into calls. We plan to start with an in-person microphone mode and a viewer for meeting records.
- **iPhone / iPad.** iOS does not allow capturing audio from other apps; not planned.

Back to the [README](../README.en.md).
