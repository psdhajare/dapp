# Best Card home-screen widget — Xcode setup (~10 min, one-time)

The widget code lives in `ios/BestCardWidget/`. Xcode must create the extension
**target** (this can't be scripted safely). Do this once in Xcode; after that,
`flutter run`/`flutter build` include the widget.

## 1. Add the widget extension target
1. Open `ios/Runner.xcworkspace` in Xcode.
2. File ▸ New ▸ Target… ▸ **Widget Extension**. Name it **BestCardWidget**.
   - Uncheck "Include Configuration App Intent" (we use a static widget).
   - Team: **6WVMR4P5U4** (same as Runner). Bundle id becomes
     `com.dapp.bestcard.BestCardWidget`.
   - When asked to "Activate scheme", click **Activate**.
3. Xcode generates a `BestCardWidget/` group with a template. **Delete** the
   template `BestCardWidget.swift` and template `Info.plist` it created (Move to
   Trash), then **Add Files to "Runner"…** and add the ones already in
   `ios/BestCardWidget/`:
   - `BestCardWidget.swift`
   - `Info.plist`  (set it as the target's Info.plist in Build Settings ▸
     Packaging ▸ Info.plist File if not auto-linked)
   - `BestCardWidget.entitlements`
   Make sure all are assigned to the **BestCardWidget** target only.

## 2. App Group (shared storage between app and widget)
Add the **App Groups** capability with id `group.com.dapp.bestcard` to BOTH:
- **Runner** target (Signing & Capabilities ▸ + Capability ▸ App Groups ▸ add
  `group.com.dapp.bestcard`).
- **BestCardWidget** target (its `.entitlements` already declares it; also add
  the capability in Signing & Capabilities so the provisioning profile includes
  it).

## 3. Point the widget target's Info.plist / entitlements
- Build Settings (BestCardWidget) ▸ **Code Signing Entitlements** =
  `BestCardWidget/BestCardWidget.entitlements`.
- Deployment target iOS 16+ (widget uses `containerBackground` guarded for 17).

## 4. Run
```
flutter run --release -d <device-id>
```
Long-press home screen ▸ + ▸ search "Best Card" ▸ add the widget.

## Data contract (already wired in Flutter)
`lib/home_widget_service.dart` writes JSON under App Group
`group.com.dapp.bestcard`, key `best_card`. The widget reads the same. Keys:
`category, issuer, name, headline, caption, primary, secondary`.

If the widget shows the placeholder, open the app once (it writes the data on
launch / after a recommendation), then the widget refreshes.
