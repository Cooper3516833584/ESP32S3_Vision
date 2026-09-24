# Camera Viewer launcher (maintainers)

The launcher only checks `GET /health` (and, for older firmware, the finite `/` page marker) before opening `http://192.168.4.1/` in the default browser. It never requests `/raw`, `/stream`, or `/metrics`.

## macOS

On macOS with Xcode Command Line Tools installed, run:

```bash
bash project/CameraWebServer/tools/camera-viewer-launcher/macOS/build_app.sh
```

This creates a universal Apple Silicon/Intel `Camera Viewer.app` and `Camera-Viewer-macOS.zip` under `macOS/dist`. The app uses AppKit and system frameworks only. It is not Developer ID signed or notarized; first launch instructions are in the student quick start.

## Windows

With the .NET 8 SDK, publish a self-contained single-file Windows GUI executable:

```powershell
dotnet publish project/CameraWebServer/tools/camera-viewer-launcher/Windows/CameraViewer.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeAllContentForSelfExtract=true `
  -o project/CameraWebServer/tools/camera-viewer-launcher/Windows/publish
```

Run the executable with `--self-test` to check the health-response validator. The release artifact contains the .NET runtime, so students do not install it separately.

## Release packaging

Push a tag matching `camera-viewer-v*`. The GitHub Actions workflow builds both launchers and publishes `Camera-Viewer-Windows.exe` plus `Camera-Viewer-macOS.zip` as Release assets. GitHub Actions builds macOS binaries on macOS; a Windows checkout cannot compile the AppKit application locally.

If a tag push does not start the workflow (for example, Actions are disabled in repository settings), enable Actions and use **Actions → Build Camera Viewer launchers → Run workflow**, selecting the release tag. Running against a tag publishes the two assets; running against `main` only builds and stores Actions artifacts.
