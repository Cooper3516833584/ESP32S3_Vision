# Camera Viewer launcher (maintainers)

The launcher only checks `GET /health` (and, for older firmware, the finite `/` page marker) before opening `http://192.168.4.1/` in the default browser. It never requests `/raw`, `/stream`, or `/metrics`.

## macOS

On macOS with Xcode Command Line Tools installed, run:

```bash
bash project/CameraWebServer/tools/camera-viewer-launcher/macOS/build_app.sh
```

The script is intended to create a universal Apple Silicon/Intel `Camera Viewer.app` and `Camera-Viewer-macOS.zip` under `macOS/dist`. The app uses AppKit and system frameworks only. The build and resulting app have not yet been verified on a Mac. It is not Developer ID signed or notarized.

## Windows

With the .NET 8 SDK, publish a self-contained single-file Windows GUI executable:

```powershell
dotnet publish project/CameraWebServer/tools/camera-viewer-launcher/Windows/CameraViewer.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeAllContentForSelfExtract=true `
  -o project/CameraWebServer/tools/camera-viewer-launcher/Windows/publish
```

Run the executable with `--self-test` to check the health-response validator. The publish command requests a self-contained build; Windows publishing has not yet been verified in this repository.

## Release packaging

**No launcher Release or downloadable binaries have been published yet.** The workflow is configured to build both launchers and, on a successful tag run, publish `Camera-Viewer-Windows.exe` plus `Camera-Viewer-macOS.zip`. Its execution and artifacts still need verification. Students should use the ESP32 browser Viewer at `http://192.168.4.1/`.

For maintainers: if a tag push does not start the workflow, inspect repository Actions settings and workflow history. A manual **Actions → Build Camera Viewer launchers → Run workflow** run on a tag is another way to request a Release build. Confirm both jobs succeed and both files appear on the Release page before documenting them as student downloads. Running against `main` only requests Actions artifacts.
