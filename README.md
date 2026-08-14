# vs-config-info

[![test](https://github.com/cyimperial/vs-config-info/actions/workflows/test.yml/badge.svg)](https://github.com/cyimperial/vs-config-info/actions/workflows/test.yml)

A [GitHub Copilot CLI](https://github.com/github/copilot-cli) skill that snapshots your local **.NET + Visual Studio** configuration.

Ask Copilot CLI things like _"show me my dotnet info"_, _"vs config"_, or _"what .NET SDKs do I have?"_ and this skill kicks in.

## ✨ Features

The skill exposes an interactive launcher with multiple output formats:

- 📋 **Text summary** — structured report of SDK, Host, runtimes, workloads, VS installs
- 🩺 **Doctor mode** — summary + diagnostics (EOL versions, arch mismatches, missing workloads…)
- 🔬 **Raw output** — unmodified `dotnet --info` in a code block
- 📸 **Screenshot** — `dotnet --info` rendered as a cmd-styled PNG
- 📁 **Folder icons** — Windows Explorer-style PNGs of `sdk` / `Microsoft.NETCore.App` / `templates`
- 🎒 **All-in-one** — bundles the screenshot + folder icons + razor matrix into one timestamped folder
- 🧪 **Razor matrix** — builds a Razor Pages app on net10/9/8 (self-contained win-x64) and renders the stacked `razor.deps.json` snippets

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

## 🚀 Setup

Install the skill by cloning it into your Copilot CLI skills folder:

```powershell
# 1. Clone into the Copilot CLI user skills directory
git clone https://github.com/cyimperial/vs-config-info.git `
  "$env:USERPROFILE\.copilot\skills\vs-config-info"
```

That's it — the next time you start `copilot`, the skill is auto-discovered via its `SKILL.md` front matter.

### Manual install (alternative)

```powershell
mkdir "$env:USERPROFILE\.copilot\skills\vs-config-info"
# Copy SKILL.md into that folder
```

## 🧪 Try it

Start Copilot CLI and try any of these prompts:

```text
vs config
dotnet info
show me my dotnet setup
what .NET SDKs do I have?
run dotnet --info as a screenshot
doctor mode
```

The skill launcher will pop up with clickable options.

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
├── .github/workflows/test.yml      # runs the test suite on windows-latest
├── docs/
│   ├── README.md                   # design rules + how to run the scripts
│   ├── scripts.md                  # script parameter reference
│   ├── testing.md                  # how to run the tests + what they cover
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
    └── Invoke-SkillTests.ps1       # 37 tests, no external dependencies
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

37 tests, no Pester or other dependency to install, all output confined to `%TEMP%`. Every
fixed defect has a named regression test. See [`docs/testing.md`](docs/testing.md).

## 📜 License

MIT — see [LICENSE](LICENSE).
