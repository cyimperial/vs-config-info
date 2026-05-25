# vs-config-info

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

## 📦 Requirements

- Windows
- [GitHub Copilot CLI](https://github.com/github/copilot-cli)
- .NET SDK on `PATH` (so `dotnet --info` resolves)
- _(Optional)_ Visual Studio Installer (for `vswhere.exe` detection)

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
├── README.md     # this file
└── SKILL.md      # the skill definition (front matter + workflow)
```

## 📜 License

MIT
