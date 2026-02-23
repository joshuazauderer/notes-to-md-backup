## Notes → Markdown Backup

Production-quality macOS (Ventura+) SwiftUI app to export Apple Notes into a structured Markdown backup ZIP.

### Running

- Open `NotesToMarkdownBackup.xcodeproj` in Xcode.
- Select the `NotesToMarkdownBackup` scheme.
- Run on macOS 13+.

### Deployment (DMG / distribution)

See `DEPLOYMENT.md` for step-by-step instructions to:

- Build a local `.app` and create a drag-to-Applications `.dmg`
- (Optional) Sign + notarize for distribution to other users

### Permissions

This app automates **Notes.app** via Apple Events. On first access macOS will prompt:

- “`Notes → Markdown Backup` would like to control `Notes`”

If you deny it, you can enable it later at:

- System Settings → Privacy & Security → Automation

### Export format

The created ZIP contains:

- `README.md`: this file (export-specific notes + limitations)
- `manifest.json`: export metadata + failures
- One folder per account (e.g. `iCloud/`, `On My Mac/`)
  - Nested folders matching Notes
  - Each note as a `.md` file with YAML frontmatter
  - Per-note `assets/` folder for extracted images/attachments (best-effort)

### Known limitations (Notes scripting)

Apple Notes’ scripting support is limited and can vary between macOS versions:

- **JXA approach**: the app uses **JXA** (`osascript -l JavaScript`) to drive Notes and returns **JSON-only** on stdout for robustness.
- **Attachments/images**: attachment export is **best-effort** via Notes scripting (writes files into per-note `assets/`). Some content types may not expose exportable `data()` and will be reported in `manifest.json` failures/logs.
- **Formatting**: Markdown conversion is pragmatic. It preserves plain text, links, images, and basic emphasis where possible; complex layouts may degrade.
- **Scale**: Export runs asynchronously and rate-limits scripting calls to keep Notes responsive, but extremely large libraries can still take time.

### Development: Mock Notes mode

In app Settings you can enable **Mock Notes mode** to develop/test without Notes automation permissions.

