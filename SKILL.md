---
name: vs-config-info
description: Reports the user's local .NET / Visual Studio configuration by running `dotnet --info` in cmd and returning the full output. Use this skill whenever the user asks about their .NET setup, installed SDKs, installed runtimes, .NET version, MSBuild version, host architecture, RID, base path, installed workloads, or any variation of "what .NET do I have installed", "show my dotnet info", "dotnet --info", "vs config", "Visual Studio config info", or troubleshooting that requires knowing the local .NET environment.
---

# vs-config-info

Reports .NET / Visual Studio configuration using tested `scripts/`.
**Never re-implement drawing code inline**.

## Running the scripts

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\<Script>.ps1" @args
```

`<skill>` is the loaded skill folder, never a hardcoded user path. Restricted execution policy
requires the process-scoped bypass above.

| Script | Purpose |
| --- | --- |
| `Get-VsConfigInfo.ps1` | Collector: machine/user, VS installs (vswhere + registry fallback), raw `dotnet --info` |
| `New-CmdScreenshot.ps1` | `dotnet --info` as a Command Prompt-styled PNG |
| `New-FolderIconImage.ps1` | A dotnet install root's subfolders as Explorer-style icon rows |
| `New-JsonSnippetImage.ps1` | JSON snippets stacked as a VS Code dark-theme PNG |
| `New-RazorMatrix.ps1` | Builds razor on several TFMs, renders the stacked `razor.deps.json` |

See [parameters](docs/scripts.md). Use the scripts' built-in safety behaviour.

## Workflow

### 1. Select a format before running scripts

For `/vs-config-info <format>`, trim whitespace and match one token case-insensitively:

| Argument | Format | Scripts |
| --- | --- | --- |
| `summary` | Text summary | `Get-VsConfigInfo.ps1` |
| `doctor` | Doctor mode | `Get-VsConfigInfo.ps1` |
| `screenshot` | Screenshot | `New-CmdScreenshot.ps1` |
| `both` | Both | `New-CmdScreenshot.ps1` + `Get-VsConfigInfo.ps1` |
| `raw` | Raw output only | `Get-VsConfigInfo.ps1` |
| `folders` | Folder icons | `Get-VsConfigInfo.ps1` + `New-FolderIconImage.ps1` |
| `all` | All-in-one | Collector + screenshot + folders + `New-RazorMatrix.ps1` |
| `razor` | Razor matrix | `New-RazorMatrix.ps1` |

A recognized format skips the launcher.
Do not forward arguments as script parameters or commands.
An unknown format (including extra tokens) must list the supported choices above and stop without
running any scripts or showing the launcher.

With no format, show the existing launcher. Preserve natural-language format requests
without showing the launcher. If interactive input is unavailable or selection fails, say:
"Choose a format directly: /vs-config-info <format>." List the supported arguments.
Stop without running scripts; never silently choose text summary.

Use `ask_user`: `message` + `requestedSchema` (string `format` with `enum` choices).

- **message:**
  ```
  🛠️  vs-config-info launcher

  I'll peek at your local .NET setup. How should I serve it?
  ```
- **format choices**, in this order:
  1. `📋  Text summary (Recommended) — SDK, Host, runtimes, workloads`
  2. `🩺  Doctor mode — summary + flag anything missing/out-of-date`
  3. `📸  Screenshot — render dotnet --info as a PNG`
  4. `🎁  Both — screenshot + summary`
  5. `🔬  Raw output only — full dotnet --info in a code block`
  6. `📁  Folder icons — screenshots of dotnet install folders (sdk / NETCore / templates)`
  7. `🎒  All-in-one — dotnet --info + folder icons as SEPARATE PNGs in one timestamped folder`
  8. `🧪  Razor matrix — tries net11/10/9/8 (slow, ~100-200 MB per framework)`
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
produces a "Path not found" image instead of an error. Save under session `files/` as
`vs-config-info-yyyy-MM-dd_HH-mm-ss`; report the folder and three filenames.

**All-in-one** — five *separate* PNGs in one timestamped folder (same naming); never merge:
`dotnet-info.png` (`-FileName`), `sdk.png`, `netcore-app.png`, `templates.png`, `razor-matrix.png`.
Require the Razor dry-run and explicit confirmation below for `/vs-config-info all`.
If declined or unavailable, produce the other four; report that the bundle omitted the razor matrix.
Report folder and filenames.

**Razor matrix** — ⚠️ Builds outside the session folder (~100-200 MB per framework). Always:

1. Dry run and show the plan — attempts, not guaranteed target support:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1"
   ```
2. Obtain explicit build confirmation via `ask_user`.
   `/vs-config-info razor` and `/vs-config-info all` select formats, not build consent.
   If confirmation is declined or unavailable, do not build or pass `-Force`; stop `razor`
   after the plan: interactive confirmation is required.
3. Only after affirmative confirmation re-run with `-Force`:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\New-RazorMatrix.ps1" -Force -Cleanup
   ```

Use available SDK/templates, not same-major SDKs or installed runtimes; a runtime alone cannot build.
Continue after failures; report all TFM statuses/errors.
[Report details](docs/scripts.md#new-razormatrixps1).

The PNG is a compact overview of target and dependency names, not a verbatim
copy of razor.deps.json. Nested asset metadata is intentionally omitted to
avoid image encoder size limits. Report the PNG together with the detailed
JSON report and per-framework runtime pack versions.

## Output style

- Never invent values that aren't in the actual command output.
- Preserve versions, paths and commit hashes verbatim — they are used for troubleshooting.
- No commentary on the features of listed SDK versions unless the user asks.
- Never hardcode a user profile path; resolve the session folder or pass `-OutputRoot`.
