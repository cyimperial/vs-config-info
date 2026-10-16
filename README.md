# vs-config-info

[![test](https://github.com/cyimperial/vs-config-info/actions/workflows/test.yml/badge.svg)](https://github.com/cyimperial/vs-config-info/actions/workflows/test.yml)

A [GitHub Copilot CLI](https://github.com/github/copilot-cli) skill that snapshots your local **.NET + Visual Studio** configuration.

Ask Copilot CLI things like _"show me my dotnet info"_, _"vs config"_, or _"what .NET SDKs do I have?"_ and this skill kicks in.

## ✨ Features

The skill supports direct format selection or an interactive launcher:

- 📋 **Text summary** — structured report of SDK, Host, runtimes, workloads, VS installs
- 🩺 **Doctor mode** — summary + diagnostics (EOL versions, arch mismatches, missing workloads…)
- 🔬 **Raw output** — unmodified `dotnet --info` in a code block
- 📸 **Screenshot** — `dotnet --info` rendered as a cmd-styled PNG
- 🎁 **Both** — screenshot + text summary
- 📁 **Folder icons** — Windows Explorer-style PNGs of `sdk` / `Microsoft.NETCore.App` / `templates`
- 🎒 **All-in-one** — bundles the screenshot + folder icons + razor matrix into one timestamped folder
- 🧪 **Razor matrix** — attempts net11/10/9/8 (self-contained win-x64) and renders successful `razor.deps.json` snippets, with a detailed report for every target

Formats that build projects are opt-in and dry-run by default.

## 📦 Requirements

- Windows (the skill uses `cmd`, `vswhere` and `System.Drawing`)
- Windows PowerShell 5.1 — this is the verified host. On PowerShell 7 the scripts detect that
  GDI+ moved to the `System.Drawing.Common` package and tell you exactly how to proceed rather
  than failing with a cryptic `Add-Type` error
- [GitHub Copilot CLI](https://github.com/github/copilot-cli)
- .NET SDK on `PATH` — the skill reports its absence rather than inventing a version, but most
  formats need it
- _(Optional)_ Visual Studio Installer (for `vswhere.exe` detection)

> The bundled scripts are launched with `-ExecutionPolicy Bypass`, so they work on a default
> `Restricted` machine without changing any system policy.

Known limitations — VS 2015 and earlier are not detected, the razor matrix is `win-x64` only, and
PowerShell 7 is unverified — are listed in
[`docs/installation.md`](docs/installation.md).

## 🚀 Setup

Install the skill by cloning it into your Copilot CLI skills folder:

```powershell
# 1. Clone into the Copilot CLI user skills directory
git clone https://github.com/cyimperial/vs-config-info.git `
  "$env:USERPROFILE\.copilot\skills\vs-config-info"
```

That's it — the next time you start `copilot`, the skill is auto-discovered via its `SKILL.md` front matter.

Copilot CLI also scans `.github/skills/` in a repository, so you can commit the skill for the
whole team instead. Full details — project-scoped installs, `/skills add`, verification steps and
troubleshooting — are in [`docs/installation.md`](docs/installation.md).

### Manual install (alternative)

```powershell
mkdir "$env:USERPROFILE\.copilot\skills\vs-config-info"
# Copy SKILL.md into that folder
```

## 🧪 Usage

### Interactive launcher

Start Copilot CLI and invoke the skill without an argument to choose an output format:

```text
/vs-config-info
```

### Choose a format directly

Add one of these arguments to skip the launcher and use the corresponding existing workflow:

| Command | Output |
| --- | --- |
| `/vs-config-info summary` | Text summary |
| `/vs-config-info doctor` | Doctor mode |
| `/vs-config-info screenshot` | Screenshot |
| `/vs-config-info both` | Screenshot + text summary |
| `/vs-config-info raw` | Raw output only |
| `/vs-config-info folders` | Folder icons |
| `/vs-config-info all` | All-in-one: separate info, folder and confirmed Razor matrix PNGs |
| `/vs-config-info razor` | Razor matrix: dry-run plan, then confirmation before builds |

Arguments are case-insensitive. Unknown formats or extra tokens, such as
`/vs-config-info unknown` or `/vs-config-info summary extra`, show the supported choices without
running scripts. If interactive input is unavailable and no format was supplied, the skill
explains how to invoke a format directly, such as `/vs-config-info summary`, and stops; it
never silently chooses text summary.

### Razor build confirmation

Both `all` and `razor` still show a dry-run plan and require explicit build confirmation
before any Razor matrix build. Selecting a format is not confirmation. If confirmation is
declined or unavailable, `razor` stops after the plan; `all` produces the other four PNGs and
reports that the Razor matrix was omitted. Direct format selection does not bypass tool
permissions or command approvals.

After confirmation, the matrix tries `dotnet new razor -f <TFM> --force` and then
`dotnet publish -r win-x64 --self-contained` in isolated per-framework folders. It uses the
available SDK and templates rather than requiring an installed SDK with the same major version
as each target. **An SDK is still required** for these commands; a runtime alone is not enough.
Self-contained publishing supplies the target runtime, so an installed target runtime is not
used as a prerequisite either.

If a target is unsupported or a command fails, the matrix records the error and continues with
the remaining frameworks. `razor-matrix.report.json`, saved beside the PNG, includes each
framework's status, failing stage, exact command, working directory, exit code, full stdout and
stderr, and any runtime packs found. The PNG contains successful targets only; partial failure
is explicitly reported. If every target fails, no new PNG is produced and the script reports
an error pointing to the JSON report. `-Cleanup` removes scratch projects, not the report.

### Natural-language prompts

You can also ask for the skill in plain language:

```text
vs config
dotnet info
show me my dotnet setup
what .NET SDKs do I have?
run dotnet --info as a screenshot
doctor mode
```

Requests that name a format use it directly; otherwise, the launcher appears.

## 📁 Output location

Generated PNGs and bundles are saved to your active Copilot CLI session folder:

```
%USERPROFILE%\.copilot\session-state\<session-id>\files\
```

## 🗂️ Repository layout

```
vs-config-info/
├── SKILL.md                        # the skill definition (front matter + workflow)
├── README.md                       # this file
├── LICENSE
├── .github/workflows/
│   ├── test.yml                    # runs the test suite on windows-latest
│   └── razor-matrix.yml            # manual-only: runs the real razor build
├── docs/
│   ├── README.md                   # design rules + how to run the scripts
│   ├── installation.md             # requirements, install, verify, troubleshooting
│   ├── scripts.md                  # script parameter reference
│   ├── testing.md                  # how to run the tests + what they cover
│   ├── test-result.md              # latest full test run, verbatim
│   ├── audit-2026-08-14.md         # skill review + scoring rubric
│   └── fixes-2026-08-14.md         # issues found and how they were fixed
├── scripts/
│   ├── VsConfigInfo.Common.ps1     # shared helpers (paths, bitmaps, disposal)
│   ├── Get-VsConfigInfo.ps1        # collector: dotnet --info + vswhere
│   ├── New-CmdScreenshot.ps1       # cmd-styled PNG
│   ├── New-FolderIconImage.ps1     # Explorer-style folder rows
│   ├── New-JsonSnippetImage.ps1    # VS Code dark-theme JSON
│   └── New-RazorMatrix.ps1         # guarded multi-TFM razor build
└── tests/
    └── Invoke-SkillTests.ps1       # 52 tests, no external dependencies
```

All rendering lives in `scripts/` so it can be parsed, executed and verified — see
[`docs/README.md`](docs/README.md) for the design rules, and
[`docs/scripts.md`](docs/scripts.md) for parameters.

## 🧰 Using the scripts directly

The scripts are standalone and work outside Copilot CLI:

```powershell
# Collect everything as JSON
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-VsConfigInfo.ps1 -AsJson

# Screenshot dotnet --info into the current session folder
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-CmdScreenshot.ps1

# Folder icons for the installed SDKs
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-FolderIconImage.ps1 `
    -Root "$env:ProgramFiles\dotnet\sdk" -OutputPath .\sdk.png

# Razor matrix - dry run first (nothing is built without -Force)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-RazorMatrix.ps1
```

> ⚠️ **Razor matrix** is the only format that writes outside the session folder. It dry-runs by
> default and needs `-Force` to build; add `-Cleanup` to remove the scratch folder afterwards.

## ✅ Running the tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1
```

52 tests, no Pester or other dependency to install, all output confined to `%TEMP%`. Every
fixed defect has a named regression test. See [`docs/testing.md`](docs/testing.md) for what the
suite covers, and [`docs/test-result.md`](docs/test-result.md) for the latest full run verbatim.

The expensive razor build is exercised separately by a manual-dispatch workflow, so it never
runs on push. See [Why the razor build is a separate, manual workflow](docs/testing.md).
