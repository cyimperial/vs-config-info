---
name: vs-config-info
description: Reports the user's local .NET / Visual Studio configuration by running `dotnet --info` in cmd and returning the full output. Use this skill whenever the user asks about their .NET setup, installed SDKs, installed runtimes, .NET version, MSBuild version, host architecture, RID, base path, installed workloads, or any variation of "what .NET do I have installed", "show my dotnet info", "dotnet --info", "vs config", "Visual Studio config info", or troubleshooting that requires knowing the local .NET environment.
---

# vs-config-info

Reports the user's local .NET / Visual Studio configuration. All rendering is done by tested
scripts in `scripts/` — **never re-implement drawing code inline**. Unverified inline snippets
were the original source of clipped labels and syntax errors.

## Running the scripts

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\<Script>.ps1" @args
```

`<skill>` is this skill's own folder, resolved from the path you were loaded from — never
hardcode a user profile path. The bypass is required: execution policy is commonly `Restricted`.

| Script | Purpose |
| --- | --- |
| `Get-VsConfigInfo.ps1` | Collector: machine/user, VS installs (vswhere + registry fallback), raw `dotnet --info` |
| `New-CmdScreenshot.ps1` | `dotnet --info` as a Command Prompt-styled PNG |
| `New-FolderIconImage.ps1` | A dotnet install root's subfolders as Explorer-style icon rows |
| `New-JsonSnippetImage.ps1` | JSON snippets stacked as a VS Code dark-theme PNG |
| `New-RazorMatrix.ps1` | Builds razor on several TFMs, renders the stacked `razor.deps.json` |

Parameters: [`docs/scripts.md`](docs/scripts.md). Rely on each script's built-in safety
behaviour rather than scripting the equivalent work yourself.

## Workflow

### 1. Launcher

Unless the user's message already names a format, ask with `ask_user` — it accepts only
`question` and `choices`, and supplies its own freeform box:

- **question:**
  ```
  🛠️  vs-config-info launcher

  I'll peek at your local .NET setup. How should I serve it?
  ```
- **choices**, in this order:
  1. `📋  Text summary (Recommended) — SDK, Host, runtimes, workloads`
  2. `🩺  Doctor mode — summary + flag anything missing/out-of-date`
  3. `📸  Screenshot — render dotnet --info as a PNG`
  4. `🎁  Both — screenshot + summary`
  5. `🔬  Raw output only — full dotnet --info in a code block`
  6. `📁  Folder icons — screenshots of dotnet install folders (sdk / NETCore / templates)`
  7. `🎒  All-in-one — dotnet --info + folder icons as SEPARATE PNGs in one timestamped folder`
  8. `🧪  Razor matrix — builds razor on net10/9/8 (slow, ~100-200 MB per framework)`
  9. `❌  Cancel`

On `Cancel`, acknowledge and stop.

### 2. Collect once, reuse

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Get-VsConfigInfo.ps1" -AsJson
```

Returns `Timestamp`, `Machine`, `User`, `DotnetFound`, `DotnetRoot`, `SdkVersion`, `SdkCount`,
`InstalledSdks[]`, `DotnetInfo` (raw text), `VisualStudio[]` and `Notes[]`.

The captured command is the cmd `dotnet --info` — do not substitute PowerShell-native variants.

### 3. Never fabricate a value

- `DotnetFound` is `false` → say so, point at <https://dotnet.microsoft.com/download>, stop.
- `SdkCount` is `0` → a runtime is present but no SDK. `SdkVersion` is `null`; do **not** report
  the `Host:` version as an installed SDK.
- No Visual Studio detected → "No Visual Studio installation detected."
- Free-form text such as `Insiders [12023.133]` is reproduced verbatim, never normalised.

## Formats

**Raw output only** — `DotnetInfo` verbatim in a fenced code block. No summary, no commentary.

**Text summary** — the raw output in a code block, then a thorough structured report under
these headings, in order, reproducing every value verbatim:

| Heading | Contents |
| --- | --- |
| 🗓️ Report Header | `Timestamp`, `Machine`, `User` |
| 🎨 Visual Studio | Per install: display name, product and build version, channel (Release / Preview / prerelease), path, product ID — or state that none were detected |
| 🧩 .NET SDK | Version (GA / preview / RC), commit hash, workload manifest version, MSBuild version |
| 🖥️ Runtime Environment | OS name, version, platform; RID and what it means (`win-x64` → 64-bit Windows); base path |
| 🧠 Host | Version, architecture, commit |
| 📦 Installed SDKs | Every SDK with its path; mark the active one (matches base path) and flag side-by-side majors |
| 🚀 Installed Runtimes | Every version, grouped by pack: `Microsoft.AspNetCore.App`, `Microsoft.NETCore.App`, `Microsoft.WindowsDesktop.App`, plus any others |
| 🧰 Workloads | Installed IDs or "none installed", workload-set mode, whether `dotnet workload restore` is needed, manifest version |
| 🌐 Other Architectures | Any "Other architectures found" section verbatim, plus any `DOTNET_ROOT*` lines |
| 📁 Global.json / Environment | Any `global.json` resolution line and any `DOTNET_*` variables |

Where a section is empty, say so explicitly ("No additional runtime packs reported") rather
than omitting it.

**Doctor mode** — the text summary plus a `🩺 Diagnostics` section flagging: SDK older than the
current LTS, or a preview/RC build; Host architecture versus SDK base path mismatch; workloads
needing restore; multiple SDKs (note which is selected and how); runtime pack gaps; install
paths outside `DotnetRoot`; end-of-life versions. For each, give what was detected, why it
matters, and a suggested action. Derive every flag from the captured output — never invent issues.

**Screenshot** —

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-CmdScreenshot.ps1"
```

The filename is derived automatically (`vs-<product version>.png`, else
`dotnet-sdk-<version>.png`, else `vs-config-info.png`) and lands in the session `files/` folder
unless you pass `-OutputRoot`, `-OutputPath` or `-FileName`. Report the saved path and which
version produced the name.

**Both** — save the screenshot first, then print the text summary, then reference the image path.

**Folder icons** — one PNG per install root, using `DotnetRoot` from the collector (it honours
`DOTNET_ROOT`); never hardcode `C:\Program Files\dotnet`:

| PNG | Root |
| --- | --- |
| `sdk.png` | `<DotnetRoot>\sdk` |
| `netcore-app.png` | `<DotnetRoot>\shared\Microsoft.NETCore.App` |
| `templates.png` | `<DotnetRoot>\templates` |

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-FolderIconImage.ps1" `
    -Root "<root>" -OutputPath "<folder>\sdk.png"
```

Each script prints `[<file>] rows=<n> verified=<bool> labels=<...>`. **Check `Verified`**: if it
is false, report the mismatch rather than presenting the image as accurate. A missing root
produces a "Path not found" image instead of an error. Save into a timestamped `MMDD-HHMM`
folder under the session `files/` directory, then report the folder and the three filenames.

**All-in-one** — five *separate* PNGs in one `MMDD-HHMM` folder; do **not** merge them:
`dotnet-info.png` (pass `-FileName`), `sdk.png`, `netcore-app.png`, `templates.png` and
`razor-matrix.png`. The last one runs real builds, so confirm first (below); if the user
declines, produce the other four and say the bundle omitted the razor matrix. Afterwards report
the folder, every filename, and a short per-framework runtimepack summary.

**Razor matrix** — ⚠️ the only format that writes outside the session folder and costs real time
and disk (~100-200 MB per framework). Always, in this order:

1. Dry run and show the plan — it reports which frameworks can actually build:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1"
   ```
2. Confirm with the user via `ask_user`.
3. Only then re-run with `-Force`:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1" -Force -Cleanup
   ```

Frameworks whose SDK is missing are skipped, not failed. Report the folder, the filename, and a
per-framework TFM + runtimepack summary.

## Output style

- Never invent values that aren't in the actual command output.
- Preserve versions, paths and commit hashes verbatim — they are used for troubleshooting.
- No commentary on the features of listed SDK versions unless the user asks.
- Never hardcode a user profile path; resolve the session folder or pass `-OutputRoot`.
