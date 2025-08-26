Packaging via GitHub Actions

Overview
- Build artifacts on CI runners: Windows installer (.exe, signed if secrets provided), Windows portable (zip), macOS signed .pkg (Apple Silicon), Linux tar.gz.
- Uses PyInstaller with `downloader.spec` (bundles `bin/` if present).
- Triggers on manual dispatch or `v*` tags; uploads artifacts and attaches to tag releases.

Workflows
- File: `.github/workflows/release.yml`
- Matrix OS: `windows-latest`, `macos-14` (Apple Silicon), `ubuntu-latest`

macOS Signing/Notarization
- Required GitHub Secrets (Organization/Repo → Settings → Secrets and variables → Actions):
  - `MACOS_CERT_P12_BASE64`: Base64-encoded Developer ID Application certificate (.p12)
  - `MACOS_CERT_PASSWORD`: Password for the .p12
  - `MACOS_SIGN_IDENTITY`: Codesign identity (app), e.g. `Developer ID Application: Your Name (TEAMID)`
  - `MACOS_INSTALLER_IDENTITY`: Installer signing identity, e.g. `Developer ID Installer: Your Name (TEAMID)`
  - `APPLE_API_KEY_BASE64`: Base64-encoded App Store Connect API key (.p8)
  - `APPLE_API_KEY_ID`: App Store Connect API Key ID (e.g., ABCDEFGHIJ)
  - `APPLE_API_ISSUER_ID`: App Store Connect Issuer ID (UUID)

- Notes
- If macOS secrets are not set, the job still builds the .pkg but will skip signing and notarization.
- Windows signing:
  - `WINDOWS_CERT_PFX_BASE64`: Base64-encoded PFX (code signing cert)
  - `WINDOWS_CERT_PASSWORD`: PFX password
  - `WINDOWS_TIMESTAMP_URL`: Optional timestamp URL (default: `https://timestamp.digicert.com`)
- Linux packaging currently produces a tar.gz. We can extend to `.AppImage` or `.deb` in a follow-up.

Windows Installer
- Script: `installer.iss` (Inno Setup).
- CI installs Inno Setup via Chocolatey and runs `iscc installer.iss`.
- Signs installer and uninstaller via Inno `SignTool` using secrets.
- Output: `installer-output\ACL-Downloader-Setup-x64.exe` uploaded as artifact and to releases.

macOS (Apple Silicon)
- Built on `macos-14` runner for arm64.
- Identifier: read from `BUNDLE_ID` (fallback: `com.acl.downloader`).
- Version: read from `VERSION` or Git tag.
- Output: `acl-downloader-mac-arm64.pkg` (signed + notarized if secrets provided). Standard installer flow into /Applications.

Local Build
- Optional: `pyinstaller -y downloader.spec` creates `dist/acl-downloader/` for all platforms and `.app` on macOS.
