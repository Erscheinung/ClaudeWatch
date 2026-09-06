# Contributor guidance

## Scope and layout

The git repository is this directory; the Xcode project and Watch sources are in `ClaudeWatch/`. Read the root README before changing interaction behavior. Preserve unrelated user changes and keep keys out of source and logs.

## Watch UX contract

- One tap begins recording; a second tap on the send arrow finishes and sends. Do not restore hold-to-talk instructions, long-press discovery, or unlabeled color-only state changes.
- Keep ready, microphone preparation, listening, processing, and answer-reading states distinct. Listening needs an explicit label, duration, send affordance, and orbit animation. Processing needs progress and cancellation.
- Answers must remain unobstructed. Use the bottom Ask control to start a new question directly. Open new answers at their beginning, not their last line.
- Keep the left-edge settings cue subtle but tappable and accessible. Preserve the right-swipe gesture and non-gesture access.
- Honor persisted Read aloud for automatic speech. Manual playback remains available with a Stop action. Render Markdown through AnswerText and derive speech using AnswerFormatting.plainText.
- Use Dynamic Type, meaningful VoiceOver labels, adequate hit targets, and Reduce Motion/reduced-luminance handling. Animate only active states.
- Cancel microphone preparation, recordings, speech, and pending requests on backgrounding/disappearance or Settings entry. Ignore stale asynchronous callbacks. Remove temporary recording files. Preserve failed-request audio only for an explicit retry.
- Text voice mode uses Gemini transcription, so it needs a Gemini key even with other answer providers. Audio mode requires Gemini. Keep setup guidance consistent with actual behavior.
- Questions are currently independent; do not imply conversation memory unless the request pipeline is updated to provide it.

## Implementation and delivery

Use existing source files where practical; the Xcode project explicitly tracks sources. Keep response rendering shared instead of displaying assistant strings with raw `Text(String)`. Update README and setup help whenever controls change.

Follow the user's validation instructions. For the September 2026 UX overhaul, the user explicitly requested implementation and commit with **no autonomous testing**. No builds, simulator launches, device runs, or test execution were performed for that change; device validation is pending. Do not claim production validation without evidence.
