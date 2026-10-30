# Building Crimson Knight (Windows .exe, Linux, installers)

The game is the Godot 4.7.2 project at the repo root. Everything below produces files in `dist/` (git-ignored).

| Output | Command |
|---|---|
| `dist/windows/CrimsonKnight.exe` (+ `ai/`) | `npm run build`, or `powershell -ExecutionPolicy Bypass -File build/build_windows.ps1` |
| `dist/CrimsonKnight-Setup.exe` | `npm run build:installer`, or `build_windows.ps1 -Installer` |
| `dist/linux/CrimsonKnight.x86_64` (+ `ai/`) | `npm run build:linux`, or `bash build/build_linux.sh` |
| `dist/CrimsonKnight-<ver>-linux-x86_64.tar.gz`, `.AppImage` | `npm run package:linux`, or `bash build/package_linux.sh` (after `build_linux.sh`) |
| Run the game from source | `npm start` |
| Logic tests | `npm test` |

Script options: `build_windows.ps1 -NoAI -DebugBuild -Installer`, `build_linux.sh --no-ai --debug`, `package_linux.sh --tar-only`.
Environment overrides: `GODOT` (Godot binary), `CK_AI_DIR` (the `ai/` folder to ship), `ISCC` (Inno Setup compiler), `APPIMAGETOOL`, `CK_VERSION` (Linux package version; the installer takes `/DAppVersion=` in `crimson_knight.iss`).

## What you need to download (once)

### 1. Godot export templates 4.7.2 (required, ~1.2 GB)
Either:
- In the Godot 4.7.2 editor: **Editor → Manage Export Templates → Download and Install**, or
- Download `Godot_v4.7.2-stable_export_templates.tpz` (1,281,349,702 bytes) from
  `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
  and install it with **Editor → Manage Export Templates → Install from File**.

They end up in `%APPDATA%\Godot\export_templates\4.7.2.stable\` (Linux: `~/.local/share/godot/export_templates/4.7.2.stable/`).
The build scripts check for `windows_release_x86_64.exe` / `linux_release.x86_64` there and stop with a clear message if they are missing.
The one `.tpz` covers both Windows and Linux, so the Linux build can be exported from Windows too (`bash build/build_linux.sh` in Git Bash).

### 2. Inno Setup 6 (Windows installer only, ~10 MB)
`innosetup-6.7.4.exe` from `https://jrsoftware.org/isdl.php` (or `https://github.com/jrsoftware/issrc/releases/tag/is-6_7_4`), or
`winget install JRSoftware.InnoSetup`. The script was written for Inno Setup 6; the build script also finds Inno Setup 7 (7.1.1 is current) but the `.iss` hasn't been tested with it.

### 3. R.E.D. AI for Linux (Linux builds only)
The `ai/` folder on Owen's PC holds **Windows** binaries; the models (`ai/models/`) work on both. For a Linux build, make a
second folder `ai_linux/` at the repo root (git-ignored and not exported, like `ai/`; put an empty `.gdignore` in it as `ai/` has) with the same layout and point the build at it with `CK_AI_DIR=/path/to/ai_linux bash build/build_linux.sh`:

```
ai_linux/
  llama/llama-server            + the lib*.so files shipped next to it
  whisper/Release/whisper-server
  piper/piper/piper             + its lib*.so, espeak-ng-data/ (the whole extracted piper/ folder)
  models/                       copy of ai/models/ (qwen2.5-1.5b-instruct-q4_k_m.gguf, ggml-base.en.bin, en_US-amy-low.onnx + .onnx.json)
```

- **llama.cpp:** `llama-b11982-bin-ubuntu-x64.tar.gz` (22.7 MB) from `https://github.com/ggml-org/llama.cpp/releases/tag/b11982`
  (same build as the Windows `llama-b11982-bin-win-cpu-x64.zip`). Copy `llama-server` and the `.so` libraries beside it into `ai_linux/llama/`.
- **whisper.cpp:** there is **no** prebuilt Linux release asset (releases only ship Windows/macOS/iOS binaries). Build it on Linux (~2 min):
  ```
  git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp
  cmake -S whisper.cpp -B whisper.cpp/build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
  cmake --build whisper.cpp/build -j --target whisper-server
  ```
  then copy `whisper.cpp/build/bin/whisper-server` to `ai_linux/whisper/Release/whisper-server`.
- **Piper:** `piper_linux_x86_64.tar.gz` (26.5 MB) from `https://github.com/rhasspy/piper/releases/tag/2023.11.14-2`.
  It extracts to `piper/`; put that folder at `ai_linux/piper/piper/`.

The game looks for `llama-server`, `whisper-server` and `piper` without `.exe` on Linux (`OS.get_name()` in `red_ai.gd` / `red_voice.gd`).

### 4. appimagetool (AppImage only, Linux, ~15 MB)
`appimagetool-x86_64.AppImage` from `https://github.com/AppImage/appimagetool/releases/tag/continuous`; `chmod +x` it and put it on
`PATH` as `appimagetool` or set `APPIMAGETOOL`. Without it, `package_linux.sh` makes only the `.tar.gz`.

## What gets shipped
- **The .exe / .x86_64** has the game packed inside (embedded PCK). Presets are in `export_presets.cfg` ("Windows Desktop", "Linux", x86_64).
  - Packed: all imported resources (models, textures, audio, scenes, scripts, UI pack) plus the JSON the game reads with `FileAccess`:
    `config/*.json`, `godot/data/*.json`, `CRIMSON_KNIGHT_UI_PACK/config/*.json`.
  - Left out: `game/`, `docs/`, `tools/`, `node_modules/`, `ai/`, `.claude/`, `assets/source/`, `godot/tools/`, `build/`, `dist/`, `legacy_v03/`, `references/`.
  - Icon: `build/icon/crimson_knight.ico` (made from `assets/images/hero/a_armor_emblem.png`); `build/icon/crimson_knight.png` for Linux.
- **`ai/`** (~1.3 GB) is copied next to the executable. `RedAI.find_ai_dir()` checks `res://ai` (running from source) and then `<exe folder>/ai`.
  Without it the game still runs; R.E.D. uses scripted lines. In a git worktree the build scripts fall back to the main checkout's `ai/`.
- **Windows installer** (`build/installer/crimson_knight.iss`): installs to Program Files (or per-user if chosen), Start menu shortcut,
  optional desktop shortcut, uninstaller, and an optional **"R.E.D. AI voice + brain (1.3 GB)"** component (on in "Full", off in "Game only").
  Saves and settings live in `%APPDATA%\Godot\app_userdata\` and survive uninstall.
- **Linux tarball:** `CrimsonKnight/` with the game, `ai/` (if built with it), `crimson-knight.desktop`, `crimson-knight.png` and
  `install-desktop-entry.sh` (adds a menu entry for the current user). **AppImage:** same content with `AppRun` and the `.desktop` file;
  it includes `ai/` if `dist/linux/ai` exists, so build with `--no-ai` for a small AppImage.

## Notes
- The first export imports every asset into `.godot/` (several minutes on a fresh checkout or worktree); later exports are quick.
- The export writes `dist/.gdignore` so Godot never scans the exported builds or the copied `ai/` as project files.
- Shell scripts are kept LF and PowerShell/Inno files CRLF via `build/.gitattributes`.


## Sharing with friends
Zip `dist/windows/` without the `ai/` folder (`build_windows.ps1 -NoAI`): about 320 MB. On first run, friends open **Settings > R.E.D. AI** and press **Download**. The game fetches and installs R.E.D.'s local AI by itself (see `docs/RED_AI.md`).
