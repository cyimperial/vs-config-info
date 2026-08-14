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

## Running the bundled scripts

All rendering is done by tested scripts in `scripts/`. **Never re-implement the drawing
code inline** — earlier inline snippets were the source of clipped labels and syntax errors.

Invoke every script like this (execution policy is commonly `Restricted`, so the bypass is required):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\<Script>.ps1" @args
```

`<skill>` is this skill's own folder — resolve it from the skill path you were loaded from.
Do not hardcode a user profile path.

| Script | Purpose |
| --- | --- |
| `Get-VsConfigInfo.ps1` | Timestamp + machine/user + VS installs (vswhere, registry fallback) + raw `dotnet --info` |
| `New-CmdScreenshot.ps1` | Renders `dotnet --info` as a Command Prompt-styled PNG |
| `New-FolderIconImage.ps1` | Renders a dotnet install root's subfolders as Explorer-style icon rows |
| `New-JsonSnippetImage.ps1` | Renders JSON snippets stacked as a VS Code dark-theme PNG |
| `New-RazorMatrix.ps1` | Builds razor on several TFMs and renders the stacked `razor.deps.json` |

Full parameter reference: [`docs/scripts.md`](docs/scripts.md).

## Workflow

### 1. Interactive launcher (always show this first)

Greet the user with a playful menu using the `ask_user` tool. Every option is clickable —
the tool automatically offers a freeform input box as well, so do **not** pass any extra
parameter for that (`ask_user` accepts only `question` and `choices`).

- **question:**
  ```
  🛠️  vs-config-info launcher

  I'll peek at your local .NET setup. How should I serve it?
  ```
- **choices** (in this exact order — the recommended option comes first):
  1. `📋  Text summary (Recommended) — SDK, Host, runtimes, workloads`
  2. `🩺  Doctor mode — summary + flag anything missing/out-of-date`
  3. `📸  Screenshot — render dotnet --info as a PNG`
  4. `🎁  Both — screenshot + summary`
  5. `🔬  Raw output only — full dotnet --info in a code block`
  6. `📁  Folder icons — screenshots of dotnet install folders (sdk / NETCore / templates)`
  7. `🎒  All-in-one — dotnet --info + folder icons as SEPARATE PNGs in one timestamped folder`
  8. `🧪  Razor matrix — builds razor on net10/9/8 (slow, ~100-200 MB per framework)`
  9. `❌  Cancel`

Skip this prompt **only** if the user's original message already specifies a format (e.g.
"just give me a screenshot", "summary please"). If they picked `Cancel`, acknowledge and stop.

### 2. Collect the configuration

Run the collector once and reuse its output for whichever format was chosen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Get-VsConfigInfo.ps1" -AsJson
```

It returns `Timestamp`, `Machine`, `User`, `DotnetFound`, `DotnetRoot`, `SdkVersion`,
`DotnetInfo` (raw text), `VisualStudio[]` and `Notes[]`.

The command run is the cmd `dotnet --info` — do **not** substitute `Get-Command dotnet` or
other PowerShell-native variants.

### 3. If `dotnet` is not found

`DotnetFound` will be `false` and `Notes` will say so. Report that clearly, suggest installing
the .NET SDK from <https://dotnet.microsoft.com/download>, and skip the rest of the workflow.
Never fabricate version information. The same rule applies to Visual Studio: if no install is
detected, say "No Visual Studio installation detected." rather than guessing a version.

### 4. Render the chosen format

Formats are described below.

## Formats

### Format: Raw output only

Paste the unmodified `DotnetInfo` text in a fenced code block. No summary, no commentary.

### Format: Text summary

Print the raw output in a fenced code block, then a **detailed** structured report. Aim for
thorough, not minimal — surface every meaningful line `dotnet --info` produces.

#### 🗓️ Report Header (always first)
- **Generated:** the collector's `Timestamp`
- **Machine:** the collector's `Machine`
- **User:** the collector's `User`

#### 🎨 Visual Studio
For **each** entry in `VisualStudio`: display name, product version, build version, channel
(Release / Preview / prerelease flag), installation path, product ID. List all installs, or
state that none were detected.

> Note: `ProductVersion` is free text and may read e.g. `Insiders [12023.133]`. Reproduce it
> verbatim; never normalise it into a version number that was not reported.

#### 🧩 .NET SDK
Version (and whether GA / preview / RC), commit hash, workload manifest version, MSBuild
version, and the language version implied by the SDK band.

#### 🖥️ Runtime Environment
OS name / version / platform, RID (and what it means, e.g. `win-x64` → 64-bit Windows), base path.

#### 🧠 Host
Version, architecture, commit.

#### 📦 Installed SDKs
Every SDK with version + install path. Note which one is active (matches Base Path) and flag
side-by-side major versions.

#### 🚀 Installed Runtimes
Group by pack and list **every** version found: `Microsoft.AspNetCore.App`,
`Microsoft.NETCore.App`, `Microsoft.WindowsDesktop.App`, plus any other packs.

#### 🧰 Workloads
Installed workload IDs (or explicitly "none installed"), workload-set mode, whether
`dotnet workload restore` is needed, manifest version.

#### 🌐 Other Architectures
Reproduce any "Other architectures found" section verbatim, plus any `DOTNET_ROOT*` lines.

#### 📁 Global.json / Environment
Any `global.json` resolution line and any `DOTNET_*` env vars surfaced by `--info`.

Preserve **all** version numbers, commit hashes and paths verbatim. If a section is empty in
the source output, say so explicitly ("No additional runtime packs reported") rather than omitting it.

### Format: Doctor mode

Run the Text summary, then add a `🩺 Diagnostics` section that flags:

- SDK major version older than current LTS, or a preview/RC build
- Mismatch between Host architecture and SDK base path (x86/x64/arm64)
- Workloads needing restore (e.g. "No workload sets are installed")
- Multiple SDK versions — note which is selected and how (`global.json`, latest, env var)
- Runtime pack gaps (e.g. ASP.NET Core present but no matching WindowsDesktop pack)
- Non-standard install paths (anything outside the reported `DotnetRoot`)
- Deprecated or end-of-life versions, with the EOL date if known

Keep diagnostics factual — derived only from the captured output. Never invent issues. For each
flag include **what** was detected, **why** it matters, and a **suggested action**
(e.g. "Run `dotnet workload restore`").

### Format: Screen capture

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-CmdScreenshot.ps1"
```

The script captures `dotnet --info`, prepends a realistic `C:\Users\<user>>dotnet --info`
prompt line, and draws it in Consolas 12pt on the real cmd palette (`#0C0C0C` background,
`#CCCCCC` text) — no banner, no dividers.

Filename is derived automatically: `vs-<product version>.png`, else
`dotnet-sdk-<version>.png`, else `vs-config-info.png` (free-form version text is sanitised
for the filesystem). Output goes to the current session `files/` folder unless you pass
`-OutputRoot` / `-OutputPath` / `-FileName`.

Report the saved path and which version produced the filename.

### Format: Both

Save the screenshot first, then print the text summary, then reference the saved image path at the end.

### Format: Folder icons

Render one PNG per dotnet install root — three total:

| PNG | Root |
| --- | --- |
| `sdk.png` | `<DotnetRoot>\sdk` |
| `netcore-app.png` | `<DotnetRoot>\shared\Microsoft.NETCore.App` |
| `templates.png` | `<DotnetRoot>\templates` |

Use `DotnetRoot` from the collector (it honours `DOTNET_ROOT` and the resolved `dotnet` on
PATH) — do **not** hardcode `C:\Program Files\dotnet`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-FolderIconImage.ps1" `
    -Root "<root>" -OutputPath "<folder>\sdk.png"
```

Each PNG shows one **horizontal row per subfolder**: a yellow Windows-style folder icon on the
**left**, the exact folder name on the **right**. The script measures every label with the same
font it draws with, sizes the bitmap to fit, and uses `NoWrap` + `Trimming::None`, so a version
like `10.0.400-preview.0.26322.102` can never be clipped to `1` or ellipsized. Rows are sorted
by version, so `9.0.17` precedes `10.0.9`.

The script prints `[<file>] rows=<n> verified=<bool> labels=<...>` and returns `Verified`.
**Check it**: if `Verified` is false, report the mismatch instead of presenting the image as accurate.
A missing root produces a single "Path not found: <root>" image rather than an error.

Save into a timestamped folder (`MMDD-HHMM`) under the session `files/` directory, then report
the folder path and the three filenames.

### Format: All-in-one (separate PNGs, one folder)

Produces **five separate PNG files** in a single `MMDD-HHMM` folder under the session `files/`
directory. Do **not** merge them into one image.

1. `dotnet-info.png` — pass `-FileName 'dotnet-info.png'` to `New-CmdScreenshot.ps1`
2. `sdk.png`
3. `netcore-app.png`
4. `templates.png`
5. `razor-matrix.png`

⚠️ Item 5 runs real builds. Because this is slow and writes outside the session folder,
**confirm with the user before starting** (see Razor matrix below). If they decline, produce
the other four and say the bundle omitted the razor matrix.

Afterwards report the folder path, every filename produced, and a short per-framework
runtimepack summary.

### Format: Razor matrix

Builds a Razor Pages app on several target frameworks (self-contained win-x64) and renders each
`razor.deps.json` targets section stacked top → bottom: net10.0, net9.0, net8.0.

⚠️ **This is the only format that writes outside the session folder and costs real time and
disk (~100-200 MB per framework).** Always:

1. Run the dry run first and show the plan — it reports which frameworks can actually build:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1"
   ```
2. Confirm with the user via `ask_user` before building.
3. Only then re-run with `-Force` (add `-Cleanup` to delete the scratch build afterwards):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1" -Force -Cleanup
   ```

Safety behaviour built into the script — rely on it rather than scripting the builds yourself:

- Each framework builds in its **own** subfolder, so `dotnet new --force` can never clobber
  another framework's project or a user's files.
- The scratch root defaults to `%LOCALAPPDATA%\vs-config-info\razor-matrix` and the script
  refuses to reuse a non-empty folder it did not create.
- Frameworks whose SDK is not installed are **skipped, not failed**.

Rendering theme (handled by `New-JsonSnippetImage.ps1`): `#1E1E1E` background, all quoted
strings — keys and values — in `#CE9178`, punctuation in `#D4D4D4`, a subtle `#404040` indent
guide, Consolas 14pt, no badge labels.

Report the folder, the filename, and a per-framework TFM + runtimepack summary.

## Output style

- Never invent values that aren't in the actual command output.
- Do not add commentary about features of listed SDK versions unless the user asks.
- Preserve versions, paths and commit hashes verbatim — they're often used for troubleshooting.
- Never hardcode a user profile path; resolve the session folder or pass `-OutputRoot`.
