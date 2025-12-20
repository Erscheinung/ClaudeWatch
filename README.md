# Claude Watch ⌚

A standalone watchOS app for interacting with Claude AI directly from your Apple Watch Ultra 3. Use voice-to-text to speak your questions and get concise AI responses on your wrist.

## Features

- **Voice Input**: Tap the microphone and speak naturally - your voice is transcribed in real-time
- **Model Selection**: Switch between Opus 4.5, Sonnet 4.5, and Haiku 4.5
- **Native watchOS UI**: Designed specifically for the Apple Watch form factor
- **Standalone Operation**: Works independently - no iPhone app required (just needs network connectivity)
- **Concise Responses**: System prompt optimized for brief, watch-friendly responses

## Screenshots

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude Watch  │    │  What's the     │    │  ⚙️ Settings    │
│                 │    │  weather like?  │    │                 │
│  🎤 Sonnet ➤   │    │                 │    │  Model: Sonnet  │
│                 │    │  It's currently │    │  API Key: ••••  │
│                 │    │  cloudy and 65° │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
    Home Screen           Chat View            Settings
```

## Requirements

- Xcode 15.0+
- watchOS 10.0+
- Apple Watch Series 6+ or Ultra (for speech recognition)
- Anthropic API key

## Project Structure

```
ClaudeWatch/
├── ClaudeWatch.xcodeproj/
├── ClaudeWatch Watch App/
│   ├── ClaudeWatchApp.swift         # App entry point
│   ├── ContentView.swift            # Main navigation
│   ├── Views/
│   │   ├── ChatView.swift           # Main chat interface
│   │   ├── SettingsView.swift       # Configuration
│   │   └── MessageBubble.swift      # Message UI component
│   ├── Models/
│   │   ├── ClaudeModel.swift        # Model definitions
│   │   └── Message.swift            # Message & API types
│   ├── Services/
│   │   ├── ClaudeAPIService.swift   # Anthropic API client
│   │   └── SpeechRecognitionService.swift  # Voice input
│   ├── Assets.xcassets/
│   └── Info.plist
└── README.md
```

## Setup & Deployment

### 1. Clone and Open Project

```bash
# Clone the repo (if from GitHub)
git clone https://github.com/YOUR_USERNAME/ClaudeWatch.git
cd ClaudeWatch

# Open in Xcode
open ClaudeWatch.xcodeproj
```

### 2. Configure Signing

1. Open the project in Xcode
2. Select the **ClaudeWatch Watch App** target
3. Go to **Signing & Capabilities**
4. Select your **Team** (Personal Team or Developer account)
5. Update the **Bundle Identifier** to something unique:
   ```
   com.yourname.ClaudeWatch.watchkitapp
   ```

### 3. Add Required Capabilities

The app needs these capabilities (should be auto-configured via Info.plist):
- **Speech Recognition** - for voice input
- **Microphone** - for audio capture

If you encounter permission issues, verify the Info.plist contains:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Claude Watch needs microphone access...</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Claude Watch uses speech recognition...</string>
```

### 4. Build and Deploy

**To Simulator:**
1. Select a Watch simulator (e.g., "Apple Watch Ultra 2")
2. Press `Cmd + R` to build and run
3. Note: Speech recognition may have limited functionality in simulator

**To Physical Watch:**
1. Connect your iPhone to your Mac
2. Ensure your Apple Watch is paired and unlocked
3. Select your watch from the device dropdown in Xcode
4. Press `Cmd + R` to build and install
5. Trust the developer certificate on your watch if prompted:
   - Settings → General → VPN & Device Management

### 5. Configure API Key

On first launch:
1. Open Claude Watch on your watch
2. Enter your Anthropic API key when prompted
3. The key is stored locally on your watch

Get your API key at: https://console.anthropic.com/

## Usage

1. **Open the app** on your Apple Watch
2. **Tap the microphone** button and speak your question
3. **Tap send** (or wait for auto-detection) to submit
4. **View the response** - scrollable if needed
5. **Tap the model badge** to switch between Opus/Sonnet/Haiku

### Tips for Best Results

- Speak clearly and at a normal pace
- Keep questions concise for the watch format
- Use Haiku for fastest responses, Opus for complex questions
- The app works best on WiFi or when your watch has cellular

## Customization

### Modify System Prompt

Edit `ClaudeAPIService.swift` to change Claude's behavior:

```swift
system: "You are Claude, responding on an Apple Watch. Keep responses brief..."
```

### Adjust Response Length

Change `max_tokens` in `ClaudeAPIService.swift`:

```swift
max_tokens: 512  // Increase for longer responses
```

### Add Custom Models

Edit `ClaudeModel.swift` to add new model options.

## Troubleshooting

### "Speech recognition not authorized"
- Go to Watch Settings → Privacy & Security → Speech Recognition
- Enable for Claude Watch

### "Network error"
- Ensure your watch has internet connectivity
- Check that your API key is valid
- Verify the Anthropic API is accessible

### App doesn't appear on watch
- Ensure your watch is paired and synced
- Try restarting both iPhone and Watch
- Reinstall via Xcode

## Security Notes

- API key is stored in UserDefaults (suitable for personal use)
- For production deployment, consider using Keychain storage
- Messages are sent directly to Anthropic's API over HTTPS

## Future Improvements

- [ ] Conversation history persistence
- [ ] Haptic feedback on response
- [ ] Complications for quick access
- [ ] Keychain storage for API key
- [ ] WatchConnectivity for iPhone companion app

## License

MIT License - Feel free to modify and use as you wish.

## Pushing to GitHub

```bash
# Initialize git and push to your private repo
cd ClaudeWatch
git init
git add .
git commit -m "Initial commit: Claude Watch app"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/ClaudeWatch.git
git push -u origin main
```

---

Built with ❤️ for the Apple Watch Ultra 3
