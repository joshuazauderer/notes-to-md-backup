## Deployment guide (DMG / distribution)

This repo builds a macOS app named **Notes → Markdown Backup** (bundle id: `com.maxhaberman.notes-to-markdown-backup`).

This document covers:

- **A. Local install for yourself** (no Apple Developer account required)
- **B. Shareable download for other users** (recommended: Developer ID signing + notarization)

---

### A) Local install for yourself (no Developer ID)

This produces a `NotesToMarkdownBackup.app`, then packages it into a DMG you can double-click and drag into Applications.

#### 1) Build the app in Xcode

- Open `NotesToMarkdownBackup.xcodeproj` in Xcode.
- In the top bar:
  - **Scheme**: `NotesToMarkdownBackup`
  - **Destination**: `My Mac`
- Build: **Product → Build** (⌘B)

#### 2) Locate the built `.app`

- Xcode: **Product → Show Build Folder in Finder**
- In Finder open: `Products/Debug/`
- You should see: `NotesToMarkdownBackup.app`

#### 3) Create a simple drag-to-Applications DMG

Open **Terminal** and run:

```bash
mkdir -p ~/Desktop/NotesToMarkdownBackup-dmg/dmg-staging

# Copy the app from the Build folder you opened in Finder.
# TIP: you can drag the .app from Finder into Terminal to paste its full path.
cp -R "/PATH/TO/NotesToMarkdownBackup.app" \
  ~/Desktop/NotesToMarkdownBackup-dmg/dmg-staging/

# Add an Applications shortcut for the drag-to-install flow.
ln -s /Applications ~/Desktop/NotesToMarkdownBackup-dmg/dmg-staging/Applications

# Create the DMG.
hdiutil create -volname "Notes → Markdown Backup" \
  -srcfolder ~/Desktop/NotesToMarkdownBackup-dmg/dmg-staging \
  -ov -format UDZO \
  ~/Desktop/NotesToMarkdownBackup.dmg
```

#### 4) Install from the DMG

- Double-click `~/Desktop/NotesToMarkdownBackup.dmg`
- Drag `NotesToMarkdownBackup.app` into the `Applications` shortcut
- Eject the DMG

#### 5) First run + permissions

- If macOS warns about an unidentified developer:
  - Right-click the app → **Open** → **Open** (one-time)
- In-app:
  - Use **Permissions…** (next to Reload) and click **Request Automation Permission**
  - Or enable it in: System Settings → Privacy & Security → Automation

---

### B) Distribute to other users (recommended path)

If you want downloads that open normally on other users’ Macs without scary warnings, use:

- **Developer ID Application signing**
- **Notarization**

This requires an Apple Developer Program membership.

#### 1) Configure signing in Xcode

- Xcode → select the `NotesToMarkdownBackup` target
- **Signing & Capabilities**
  - Enable **Automatically manage signing**
  - Pick your **Team**

#### 2) Archive and export a signed app

- Xcode: **Product → Archive**
- In Organizer:
  - Select your archive → **Distribute App**
  - Choose **Developer ID**
  - Export the signed `.app`

#### 3) Notarize and staple (command line)

From the folder containing your exported `.app`:

```bash
# Create a zip for notarization submission
ditto -c -k --keepParent "NotesToMarkdownBackup.app" "NotesToMarkdownBackup.zip"

# Submit to Apple Notary Service (wait for the result)
xcrun notarytool submit "NotesToMarkdownBackup.zip" \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD" \
  --wait

# Staple the ticket to the app
xcrun stapler staple "NotesToMarkdownBackup.app"

# Verify
spctl -a -vv "NotesToMarkdownBackup.app"
```

#### 4) Build a DMG containing the notarized app

```bash
mkdir -p dmg-staging
cp -R "NotesToMarkdownBackup.app" dmg-staging/
ln -s /Applications dmg-staging/Applications

hdiutil create -volname "Notes → Markdown Backup" \
  -srcfolder dmg-staging \
  -ov -format UDZO \
  "NotesToMarkdownBackup.dmg"
```

Optionally notarize + staple the DMG as well:

```bash
xcrun notarytool submit "NotesToMarkdownBackup.dmg" \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "NotesToMarkdownBackup.dmg"
```

---

### Notes about permissions and user guidance

This app automates **Notes.app** via Apple Events. Users must allow:

- System Settings → Privacy & Security → Automation → enable **Notes → Markdown Backup** for **Notes**

The app includes:

- a first-run **Permissions Required** sheet
- **Help → Permissions…** and a **Permissions…** link in the main UI

