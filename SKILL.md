---
name: vs-config-info
description: Reports the user's local .NET / Visual Studio configuration by running `dotnet --info` in cmd and returning the full output. Use this skill whenever the user asks about their .NET setup, installed SDKs, installed runtimes, .NET version, MSBuild version, host architecture, RID, base path, installed workloads, or any variation of "what .NET do I have installed", "show my dotnet info", "dotnet --info", "vs config", "Visual Studio config info", or troubleshooting that requires knowing the local .NET environment.
---

# vs-config-info

You are a focused helper that reports the user's local .NET configuration by invoking the `dotnet` CLI.

## When this skill is invoked

Triggered by anything that hints at "show me my .NET / VS setup" — including but not limited to:

- "What .NET SDKs do I have?"
- "Show me my dotnet info"
- "What's my Visual Studio / .NET config?"
- "Run dotnet --info"
- Short triggers: `vs config`, `dotnet info`, `vsinfo`, `/vs-config`
- Any troubleshooting where the installed SDK / runtime / RID / base path matters.

## Workflow

### 1. Interactive launcher (always show this first)

Greet the user with a playful menu using the `ask_user` tool. **Do not require them to type anything** — every option is clickable.

- **question:**
  ```
  🛠️  vs-config-info launcher

  I'll peek at your local .NET setup. How should I serve it?
  ```
- **choices** (in this exact order):
  1. `📸  Screenshot — render dotnet --info as a PNG`
  2. `📋  Text summary (Recommended) — SDK, Host, runtimes, workloads`
  3. `🎁  Both — screenshot + summary`
  4. `🔬  Raw output only — full dotnet --info in a code block`
  5. `🩺  Doctor mode — summary + flag anything missing/out-of-date`
  6. `📁  Folder icons — screenshots of dotnet install folders (sdk / NETCore / templates)`
  7. `🎒  All-in-one — dotnet --info + folder icons as SEPARATE PNGs in one timestamped folder`
  8. `🧪  Razor matrix — build razor on net10/9/8 (self-contained win-x64) and snapshot razor.deps.json stacked top→down`
  9. `❌  Cancel`
- **allow_freeform:** `true` (so power users can still type a custom request, but it isn't required)

Skip this prompt **only** if the user's original message already specifies a format (e.g. "just give me a screenshot", "summary please"). If they picked `Cancel`, acknowledge and stop.

### 2. Run the command via cmd

Run **all three** of these so the report can include a timestamp, Visual Studio version, and the dotnet info:

```powershell
# Timestamp (local time, ISO 8601 + friendly)
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"

# Visual Studio installations via vswhere (ships with VS Installer)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vs = & $vswhere -all -prerelease -format json | ConvertFrom-Json
    # Each entry has: displayName, catalog.productDisplayVersion, installationVersion,
    # installationPath, isPrerelease, productId, channelId
}

# .NET info
$dotnet = cmd /c "dotnet --info" | Out-String
```

If `vswhere.exe` is missing, fall back to scanning `HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup\Instances\*` or report "Visual Studio not detected (vswhere.exe not found)". Never fabricate a VS version.

   ```
   cmd /c "dotnet --info"
   ```

   Do **not** use `Get-Command dotnet` or other PowerShell-native variants — the request is specifically for the cmd `dotnet --info` output.

3. **If `dotnet` is not found**, report that clearly and suggest installing the .NET SDK from <https://dotnet.microsoft.com/download>. Do not attempt to fabricate version information. Skip the rest of the workflow.

### Format: Raw output only

Just paste the unmodified `dotnet --info` output in a fenced code block. No summary, no commentary.

### Format: Doctor mode

Run the **detailed** text-summary format above, then add a `🩺 Diagnostics` section that flags:

- SDK major version older than current LTS, or running on a preview/RC build
- Mismatch between Host architecture and SDK base path (x86/x64/arm64)
- Workloads listed as needing restore (e.g. "No workload sets are installed")
- Multiple SDK versions present — note which is selected and how (`global.json`, latest, env var)
- Runtime pack gaps (e.g. ASP.NET Core installed but no matching WindowsDesktop pack when project needs it)
- Preview / unsupported builds
- Non-standard install paths (anything outside `C:\Program Files\dotnet`)
- Any deprecated or end-of-life versions, with the EOL date if known

Keep diagnostics factual — derived only from the captured output. Never invent issues. For each flag, include: **what** was detected, **why** it matters, and a **suggested action** (e.g. "Run `dotnet workload restore`").

### Format: Text summary

Return the raw command output in a fenced code block, then a **detailed** structured report. Aim for thorough, not minimal — surface every meaningful line `dotnet --info` produces. Always lead with a header block, then the sectioned report.

#### 🗓️ Report Header (always first)
- **Generated:** `<local datetime, e.g. 2026-05-23 00:05:40 +08:00>`
- **Machine:** `$env:COMPUTERNAME`
- **User:** `$env:USERNAME`

#### 🎨 Visual Studio
For **each** VS installation reported by `vswhere`:
- **Display name** (e.g. *Visual Studio Enterprise 2022*)
- **Product version** (`catalog.productDisplayVersion`, e.g. `17.12.4`)
- **Build version** (`installationVersion`)
- **Channel** (Release / Preview / Pre-release flag)
- **Installation path**
- **Product ID** (e.g. `Microsoft.VisualStudio.Product.Enterprise`)

If multiple are installed, list all of them. If none, write **"No Visual Studio installation detected."**

#### 🧩 .NET SDK
- **Version** (and whether it's GA / preview / RC)
- **Commit** hash
- **Workload manifest version**
- **MSBuild version**
- **Language versions implied** (e.g. SDK 10.0.x → C# 14 default)

#### 🖥️ Runtime Environment
- **OS Name / Version / Platform**
- **RID** (and what it means, e.g. `win-x64` → 64-bit Windows)
- **Base Path** (where the selected SDK lives)

#### 🧠 Host
- **Version**
- **Architecture**
- **Commit**

#### 📦 Installed SDKs
- List **every** SDK with version + install path
- Note which one is currently active (matches Base Path)
- Flag side-by-side major versions if present

#### 🚀 Installed Runtimes
Group by pack and list **every** version found:
- `Microsoft.AspNetCore.App` — versions + paths
- `Microsoft.NETCore.App` — versions + paths
- `Microsoft.WindowsDesktop.App` — versions + paths
- Any other packs (e.g. `Microsoft.iOS.Runtime.*`, `Microsoft.Android.Runtime.*`)

#### 🧰 Workloads
- Installed workload IDs (or explicitly say "none installed")
- Workload-set mode (`workload sets` vs `loose manifests`)
- Whether `dotnet workload restore` is needed
- Manifest version

#### 🌐 Other Architectures
- Any "Other architectures found" section reproduced verbatim
- Any `DOTNET_ROOT*` environment variable lines

#### 📁 Global.json / Environment
- Mention any `global.json` resolution line in the output
- Any `DOTNET_*` env vars surfaced by `--info`

Preserve **all** version numbers, commit hashes, and paths verbatim. If a section is empty in the source output, say so explicitly ("No additional runtime packs reported") rather than omitting it.

### Format: Screen capture

Render the cmd output as an actual PNG image (not just a code block screenshot) and save it to the session folder, styled to **match a real Command Prompt window** — exactly what the user would see if they ran the command themselves.

1. Run `cmd /c "dotnet --info"` and capture stdout as a string.
2. Prepend a single prompt line in the same style as cmd: `C:\Users\<user>>dotnet --info` so the screenshot reads like a real terminal session.
3. Use PowerShell + `System.Drawing` to draw the text onto a bitmap with **Consolas 12pt**, **black background (#0C0C0C)**, **light-gray text (#CCCCCC)**. No header banner, no colored section dividers — keep it clean cmd-style.
4. **Filename convention** — name the PNG after the detected version, in this priority order:
   - If Visual Studio is detected via `vswhere`, use the highest `catalog.productDisplayVersion` → `vs-<version>.png` (e.g. `vs-17.12.4.png`).
   - Otherwise, fall back to the .NET SDK version from the first line of `dotnet --info` → `dotnet-sdk-<version>.png` (e.g. `dotnet-sdk-10.0.300.png`).
   - If neither can be parsed, use `vs-config-info.png`.
5. Save to `C:\Users\v-cimperial\.copilot\session-state\<session-id>\files\<filename>.png`.
6. Report both the saved path and the version that was used to derive the filename.

Reference snippet (adapt path + size to fit the captured text):

```powershell
$text = cmd /c "dotnet --info" | Out-String
Add-Type -AssemblyName System.Drawing
$font = New-Object System.Drawing.Font('Consolas', 12)
$lines = $text -split "`r?`n"
$tmpBmp = New-Object System.Drawing.Bitmap 1, 1
$tmpG   = [System.Drawing.Graphics]::FromImage($tmpBmp)
$width  = ($lines | ForEach-Object { $tmpG.MeasureString($_, $font).Width } | Measure-Object -Maximum).Maximum
$height = $lines.Count * $font.Height + 20
$bmp = New-Object System.Drawing.Bitmap ([int]($width + 40)), ([int]$height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::LightGray)
$y = 10
foreach ($l in $lines) { $g.DrawString($l, $font, $brush, 20, $y); $y += $font.Height }
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
```

### Format: Both

Save the screenshot first, then print the text summary, then reference the saved image path at the end.

### Format: Folder icons

Render Windows File Explorer-style folder icon screenshots for each subfolder found in **all three** of these install roots:

1. `C:\Program Files\dotnet\sdk`
2. `C:\Program Files\dotnet\shared\Microsoft.NETCore.App`
3. `C:\Program Files\dotnet\templates`

Rules:

- **One PNG per source root**, three PNGs total. Each PNG shows the subfolder(s) inside that root as **horizontal list rows** — small Windows-style yellow folder icon on the **left**, version name on the **right** — matching the reference look the user provided. Do NOT use a grid with labels underneath; use one row per subfolder.
- If a root is missing, render a single PNG with text "Path not found: <root>".
- **Accuracy is mandatory.** Each label MUST be the EXACT, COMPLETE subfolder name returned by `Get-ChildItem -Directory` (e.g. `10.0.300`, not `1` or `10.0`). Verify before saving:
  - Measure each label's width with `Graphics.MeasureString` using the SAME font you'll draw with, then size the bitmap width to `iconWidth + padding + ceil(maxLabelWidth) + rightMargin`.
  - When calling `DrawString`, pass a `PointF` (or a `RectangleF` whose width ≥ the measured label width + a few pixels). Do NOT reuse a fixed-width rect from the grid-style folder-icon snippet — that snippet centers labels under icons and will clip horizontal rows.
  - Set `StringFormat.FormatFlags = NoWrap` and `Trimming = None` so versions like `10.0.300` are never wrapped or ellipsized to `1` / `10.0…`.
  - After saving, sanity-check: the number of rows in the PNG must equal `(Get-ChildItem $root -Directory).Count`, and each row's label text must exactly match one of those directory names.
- **Output folder name** — derive from local time using the format `MMDD-HHMM` (e.g. `0523-1216`). Create:
  `C:\Users\v-cimperial\.copilot\session-state\<session-id>\files\<MMDD-HHMM>\`
- **PNG filenames** inside that folder:
  - `sdk.png`
  - `netcore-app.png`
  - `templates.png`
- Folder icon style: yellow body (#FFC83D-ish), darker yellow tab/back, transparent/dark-gray background to match Explorer's dark-mode look. Filename text rendered in Segoe UI 10pt, white/near-white, centered below the icon.
- After generating, report the folder path and the three filenames.

Reference snippet for drawing one folder icon (adapt for grid layout):

```powershell
function Draw-FolderIcon($g, $x, $y, $size, $label) {
    $back = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 178, 51))
    $front = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 207, 87))
    # Back tab
    $tab = New-Object System.Drawing.Rectangle ($x + [int]($size*0.05)), ($y + [int]($size*0.18)), [int]($size*0.45), [int]($size*0.12)
    $g.FillRectangle($back, $tab)
    # Folder body
    $body = New-Object System.Drawing.Rectangle ($x + [int]($size*0.03)), ($y + [int]($size*0.28)), [int]($size*0.94), [int]($size*0.55))
    $g.FillRectangle($front, $body)
    # Label
    $font = New-Object System.Drawing.Font('Segoe UI', 10)
    $fmt  = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF ([single]$x, [single]($y + $size + 4), [single]$size, 30)
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.DrawString($label, $font, $white, $rect, $fmt)
}
```

### Format: All-in-one (separate PNGs, one folder)

One launcher choice that produces **five separate PNG files** saved into a single `MMDD-HHMM` timestamped folder under the session `files/` directory. Do NOT merge them into a single image — keep them as distinct files.

Files produced:

1. `dotnet-info.png` — cmd-styled `dotnet --info` screenshot (same look as the **Screen capture** format, but with this fixed filename for the bundle).
2. `sdk.png` — horizontal folder icons for `C:\Program Files\dotnet\sdk` (same look as **Folder icons**).
3. `netcore-app.png` — horizontal folder icons for `C:\Program Files\dotnet\shared\Microsoft.NETCore.App`.
4. `templates.png` — horizontal folder icons for `C:\Program Files\dotnet\templates`.
5. `razor-matrix.png` — stacked razor.deps.json snippets for net10.0 / net9.0 / net8.0 (same look as **Razor matrix**). The bundle MUST run the full razor build sequence (`dotnet new razor -f netX.0 --force` + `dotnet publish -r win-x64 --self-contained` for each TFM) to produce this file.

After generating, report the folder path and list all five filenames produced, plus a short per-framework runtimepack summary from the razor builds.

### Format: Razor matrix (build net10/9/8 and snapshot deps.json)

Build a Razor Pages template on three target frameworks (self-contained win-x64) and render a single combined PNG showing each `razor.deps.json` snippet stacked **top → bottom in this order**: net10.0, net9.0, net8.0.

Sequence (run from `C:\Users\v-cimperial\razor` — create it if missing):

```cmd
md razor
cd razor
:: For each TFM in 10.0, 9.0, 8.0
dotnet new razor -f netX.0 --force
dotnet publish -r win-x64 --self-contained
```

For each TFM, locate the generated `bin\Release\netX.0\win-x64\publish\razor.deps.json`, and extract the **targets** section showing:

- `".NETCoreApp,Version=vX.0"` (empty `{}`)
- `".NETCoreApp,Version=vX.0/win-x64"` with the `razor/1.0.0` entry, its `dependencies`, and `runtimepack.Microsoft.NETCore.App.Runtime.win-x64` / `runtimepack.Microsoft.AspNetCore.App.Runtime.win-x64` lines.

Render each snippet as **VS Code dark-theme JSON** (matching the user's reference image):

- Background: `#1E1E1E`
- **All quoted strings** (keys AND values) in orange `#CE9178`
- Punctuation `{ } [ ] , :`: light gray `#D4D4D4`
- Subtle vertical indent guide line in `#404040` on the left edge of each snippet
- Font: **Consolas 14pt**, line height = font height + 2px
- **No badge labels** — the version numbers inside the JSON identify each snippet

Stack all three vertically (10 on top, 9 middle, 8 bottom) into a single PNG.

**Filename:** `razor-matrix.png`
**Folder:** the standard `MMDD-HHMM` timestamped folder under session `files/`.

After generating, report the folder and filename, plus a short per-framework summary (TFM + runtimepack versions detected).

## Output style

- Never invent values that aren't in the actual command output.
- Do not add commentary about features of listed SDK versions unless the user asks.
- Preserve versions, paths, and commit hashes verbatim — they're often used for troubleshooting.
