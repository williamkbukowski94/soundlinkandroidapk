# soundLInk iPhone receiver

Native SwiftUI receiver for the Android host's existing TCP audio protocol. Includes nonce/HMAC group authentication, clock synchronization, scheduled AVAudioEngine playback, manual timing correction, and separate phone/Bluetooth output modes. It does not capture Spotify or other iPhone apps.

A remote macOS GitHub Actions runner generates the Xcode project with XcodeGen and checks a simulator build. No Mac is needed on the Ubuntu development machine. This build does not establish physical speaker synchronization or real iPhone compatibility; those need device testing.

## Build on a Mac or macOS runner

Install Xcode and XcodeGen. Run `xcodegen generate` inside ios, then `xcodebuild -project SoundLink.xcodeproj -scheme SoundLink -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`.

For installation, open the generated project, select an Apple signing team and an iPhone, and build for the device. Public distribution via TestFlight/App Store requires Apple Developer Program enrollment and signing setup. This repository does not contain signing credentials. A simulator app or unsigned archive cannot be installed by downloading it on an ordinary iPhone.

No installable IPA or TestFlight link is available yet. The website must keep the iPhone section explicitly unavailable until a valid signed distribution link exists.

Use the Android host address/code, with the same speaker mode. Connect Bluetooth using Control Center before joining. Playback uses estimated device output latency and a shared future timeline; calibration is required. Keep the app visible for initial tests. No acoustic accuracy claim has been verified.
