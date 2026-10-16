# Script reference

All scripts live in `scripts/` and target **Windows PowerShell 5.1** with `System.Drawing`.
See [Host compatibility](#host-compatibility) for PowerShell 7 behaviour.

Invoke them with an execution-policy bypass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\<Script>.ps1" @args
```

> **Note on `-File` and object output.** `powershell -File` flattens returned objects to text,
> so every image script also prints a one-line summary (`[file.png] rows=4 verified=True ...`)
> that survives that flattening. Multi-line array parameters are also mangled by `-File`;
> call such scripts in-process (`& .\script.ps1`) from within a bypass session instead.

---

## `VsConfigInfo.Common.ps1`

Dot-sourced helper library. Not run directly.

| Function | Purpose |
| --- | --- |
| `Get-VsConfigDrawingPlan` | Pure: decides which drawing assembly the current host needs |
| `Initialize-VsConfigDrawing` | Loads GDI+ using that plan, with an actionable error if it cannot |
| `Get-VsConfigOutputRoot` | Resolves the artifact folder: `-OutputRoot` → `$env:COPILOT_SESSION_FILES` → newest `~/.copilot/session-state/*/files` → `$env:TEMP\vs-config-info` |
| `New-VsConfigTimestampFolder` | Creates a `vs-config-info-yyyy-MM-dd_HH-mm-ss` folder under the resolved root, using local time |
| `Get-DotnetRootPath` | `$env:DOTNET_ROOT` → resolved `dotnet` on PATH → `%ProgramFiles%\dotnet` |
| `Get-DotnetInstallRoots` | Returns the `sdk`, `netcore-app` and `templates` roots |
| `Get-JsonProperty` | Reads a dotted path off a `ConvertFrom-Json` object, returning a default instead of throwing under `Set-StrictMode` |
| `ConvertTo-SortableVersion` | Extracts the first dotted-numeric run from free-form text so rows sort numerically |
| `ConvertTo-SafeFileNamePart` | Sanitises a version/product string into a filename fragment |
| `Format-JsonIndent` | Re-indents PS 5.1's ragged `ConvertTo-Json` output to canonical 2-space JSON |
| `New-VsConfigBitmap` | Bitmap + Graphics with antialiasing and ClearType enabled |
| `New-VsConfigStringFormat` | `StringFormat` with `NoWrap` and `Trimming::None` so labels never clip |
| `Save-VsConfigBitmap` | Saves PNG and disposes both Bitmap and Graphics in a `finally` |

> **Why `Get-JsonProperty` exists.** Under `Set-StrictMode -Version Latest`, reading a property
> that a JSON object does not carry throws `PropertyNotFoundStrict`. `vswhere` output varies by
> install — a minimal instance has no `catalog` node at all — so every optional property is read
> through this helper rather than with `$json.catalog.productDisplayVersion`.

### Host compatibility

Dot-sourcing `VsConfigInfo.Common.ps1` calls `Initialize-VsConfigDrawing`, so every script gets
GDI+ or a usable explanation:

| Host | Assembly | Result |
| --- | --- | --- |
| Windows PowerShell 5.1 | `System.Drawing` (GAC) | Loads. This is the verified host. |
| PowerShell 7 on Windows | `System.Drawing.Common` | Loads **if the package is installed**; otherwise throws a message naming both remedies. |
| Any non-Windows host | — | Refused up front: the skill also needs `cmd`, `vswhere` and the registry. |

The decision lives in `Get-VsConfigDrawingPlan`, which performs no loading. Keeping it pure is
what lets the test suite exercise the PowerShell 7 and non-Windows branches from 5.1, where
they would otherwise never execute:

```powershell
Get-VsConfigDrawingPlan -Edition Core -OnWindows $true
# Supported = True, AssemblyName = System.Drawing.Common, NeedsPackage = True
```

---

## `Get-VsConfigInfo.ps1`

Collects the whole configuration in one pass.

| Parameter | Description |
| --- | --- |
| `-AsJson` | Emit JSON instead of a PowerShell object |

**Returns:** `Timestamp`, `Machine`, `User`, `DotnetFound`, `DotnetRoot`, `SdkVersion`,
`SdkCount`, `InstalledSdks[]`, `DotnetInfo` (raw `dotnet --info` text), `VisualStudio[]`,
`Notes[]`.

`SdkVersion` is parsed **only** from the `.NET SDK:` block of `dotnet --info`. When no SDK is
installed that block is absent, so `SdkVersion` is `$null`, `SdkCount` is `0`, and `Notes`
records the fact. It is never back-filled from the `Host:` version — a host runtime is not an
SDK, and reporting one as the other would invent a configuration the machine does not have.

Visual Studio detection uses `vswhere -all -prerelease -format json`, falling back to
`HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup\Instances`. When neither yields a result, `Notes`
explains why and `VisualStudio` is empty — the script never guesses a version.

---

## `New-CmdScreenshot.ps1`

Renders a cmd command as a Command Prompt-styled PNG (`#0C0C0C` background, `#CCCCCC` text,
Consolas 12pt) with a realistic prompt line prepended.

| Parameter | Default | Description |
| --- | --- | --- |
| `-Command` | `dotnet --info` | Command to run and capture |
| `-OutputPath` | — | Explicit PNG path; overrides name derivation |
| `-OutputRoot` | session `files/` | Folder to write into |
| `-FileName` | derived | Fixed filename, e.g. `dotnet-info.png` for the All-in-one bundle |

**Filename derivation:** highest VS `productDisplayVersion` → `vs-<version>.png`, else SDK
version → `dotnet-sdk-<version>.png`, else `vs-config-info.png`. Free-form version text is
sanitised, so `Insiders [12023.133]` becomes `vs-Insiders-12023.133.png`.

---

## `New-FolderIconImage.ps1`

Renders a folder's subfolders as Explorer-style rows: yellow folder icon left, exact name right.

| Parameter | Default | Description |
| --- | --- | --- |
| `-Root` | *(required)* | Folder whose subfolders are rendered |
| `-OutputPath` | *(required)* | PNG path |
| `-IconSize` | `48` | Icon height in pixels |

**Returns:** `Path`, `Root`, `Labels`, `RowCount`, `Verified`, `Message`.

Guarantees:

- Labels are measured with the drawing font and the bitmap is sized to fit, so long versions
  such as `10.0.400-preview.0.26322.102` are never clipped.
- Labels are drawn at a `PointF`, never inside a fixed-width rectangle.
- Rows sort by version, so `9.0.17` precedes `10.0.9`.
- After saving, row count and label text are compared against `Get-ChildItem -Directory`;
  the result is exposed as `Verified`. **Callers should check it.**
- A missing root yields a `Path not found: <root>` image instead of an exception.

---

## `New-JsonSnippetImage.ps1`

Renders JSON snippets stacked vertically in the VS Code dark theme.

| Parameter | Description |
| --- | --- |
| `-Snippet` | One or more JSON strings, rendered top-to-bottom in order |
| `-OutputPath` | PNG path |

Theme: `#1E1E1E` background, quoted strings (keys *and* values) `#CE9178`, punctuation
`#D4D4D4`, `#404040` indent guide, Consolas 14pt, line height = font height + 2.

Two rendering details worth knowing:

- `Format-JsonIndent` re-indents to a canonical 2-space style and collapses `{}` / `[]`.
  Windows PowerShell 5.1's `ConvertTo-Json` emits ragged indentation that pushes closing braces
  far right; normalising cut one test image from 1822 px to 810 px wide.
- GDI+ trims leading spaces and pads each `DrawString` call. Indentation is therefore applied as
  an explicit x-offset (`indent × measured char width`) and text is measured with
  `GenericTypographic` so multi-coloured runs on one line do not drift apart.

---

## `New-RazorMatrix.ps1`

Builds a Razor Pages app per framework and renders the stacked `razor.deps.json` targets.
The PNG is a compact overview of target and dependency names; nested asset metadata is
omitted to keep self-contained runtime inventories within image encoder size limits.

| Parameter | Default | Description |
| --- | --- | --- |
| `-Framework` | `net11.0, net10.0, net9.0, net8.0` | Frameworks, attempted and rendered top-to-bottom |
| `-WorkRoot` | `%LOCALAPPDATA%\vs-config-info\razor-matrix` | Scratch build folder |
| `-OutputPath` | `razor-matrix.png` in a timestamped folder | PNG path |
| `-OutputRoot` | session `files/` | Base folder for the timestamped output folder |
| `-Force` | off | **Required to actually build.** Without it the script only prints its plan |
| `-Cleanup` | off | Delete the work root when finished |
| `-AllowExistingWorkRoot` | off | Permit reusing a pre-existing, non-empty work root |

Safety behaviour:

- **Dry run by default.** Nothing is created without `-Force`. A valid dry-run request returns
  `DryRun`, `Plan`, `WorkRoot`, `Path = $null`, `InstalledSdks` and `SdkProbe`. Missing `dotnet`
  or SDKs are explained in the plan; `-Force` then fails before creating scratch projects.
- **Per-framework isolation.** Each TFM builds in its own subfolder, so `dotnet new --force`
  cannot clobber another framework's project or a user's files.
- **Work-root guard.** Refuses to run against an existing non-empty folder unless it finds the
  `.vs-config-info` marker it writes itself.
- **No same-major SDK gate.** Any installed SDK enables attempts for every requested target.
  `Plan.Supported` means eligible to attempt, not proven template/SDK compatibility.
  With only a .NET 10 SDK, the dry run still plans:
  ```
    net11.0   attempt new + self-contained publish (win-x64)
    net10.0   attempt new + self-contained publish (win-x64)
    net9.0    attempt new + self-contained publish (win-x64)
    net8.0    attempt new + self-contained publish (win-x64)
  ```
- **Actual command results determine support.** Per isolated target folder, run
  `dotnet new razor -f <TFM> -n razor --force --output .`, then
  `dotnet publish -r win-x64 --self-contained -o <unique-publish-folder>`.
  Normal SDK/template resolution applies, including any applicable `global.json`. No SDK,
  runtime or template is installed by this script. Restore can download targeting/runtime
  packs needed by the self-contained publish. A runtime-only installation cannot build.
- **Compact PNG.** The image preserves target/dependency names and runtime pack versions,
  not the complete deps JSON. Nested asset metadata is omitted to avoid image encoder size
  limits; empty target objects are supported. Report the image with the detailed JSON report.
- **Continue after failure.** A failed creation skips publishing that target, not the rest of
  the matrix. Publish errors, missing deps files, malformed JSON and missing `targets` sections
  are also recorded per framework. Only successful targets enter the PNG.
- **Persistent detailed report.** `<image-stem>.report.json` is saved beside the PNG, outside
  `WorkRoot`, and survives `-Cleanup`. It includes `Succeeded` (all targets succeeded), `Path`,
  `ReportPath`, `WorkRoot`, `InstalledSdks`, `SdkProbe`, `Results` (all requested targets) and
  `Frameworks` (successful targets with runtime packs). Each result has `Framework`, `Status`,
  `Stage`, `Directory`, `Commands`, `Error`, `DepsPath` and `RuntimePacks`; each command records
  `Command`, `Directory`, `ExitCode`, `StdOut` and `StdErr` without truncation.
  `DepsPath` describes the build location and no longer exists after cleanup.
- **Explicit incomplete results.** Partial failure warns and returns `Succeeded = false`
  alongside the successful image and full report. Total failure saves the report and throws;
  no new PNG is produced. Callers must inspect `Succeeded`/`Results`, not just PNG existence.
  For each failed TFM, report its stage, command, exit code and actual output, explain only
  causes supported by that output, and suggest an appropriate next step (for example, use an
  SDK/template that supports the target or resolve the reported package restore error).
