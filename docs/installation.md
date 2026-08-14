# Installation

`vs-config-info` is a [GitHub Copilot CLI](https://github.com/github/copilot-cli) skill. Installing
it means putting the folder somewhere the CLI scans for skills — there is nothing to build and no
dependency to restore.

## Requirements

| Requirement | Why | If it is missing |
| --- | --- | --- |
| Windows | The skill uses `cmd`, `vswhere` and GDI+ (`System.Drawing`) | Not supported; the scripts refuse with a reason rather than half-working |
| Windows PowerShell 5.1 | The verified host — ships with Windows, nothing to install | See [PowerShell 7](#powershell-7) below |
| GitHub Copilot CLI | Loads and runs the skill | `npm install -g @github/copilot` |
| Git | Only for the clone install method | Download the repository as a ZIP instead |
| .NET SDK on `PATH` | Most formats report on it | The skill says so instead of inventing a version — see [no SDKs installed](#no-sdks-installed) |
| Visual Studio Installer | Supplies `vswhere.exe` for VS detection | The VS section is reported as unavailable |

Check the two that matter:

```powershell
copilot --version
$PSVersionTable.PSVersion    # 5.1.x is expected
```

## Limitations

Worth knowing before you install — none of these are bugs, and several are deliberate choices to
avoid reporting something the skill cannot actually confirm.

| Area | Limitation |
| --- | --- |
| Platform | **Windows only.** The skill depends on `cmd`, `vswhere` and GDI+. On other platforms the scripts refuse with a reason rather than half-working |
| Host | Windows PowerShell 5.1 is the only **verified** host. PowerShell 7 is detected and explained, but has never been run end to end — only the decision logic is covered by tests |
| Visual Studio | Detection uses `vswhere.exe` from its fixed Installer location, queried with `-all -prerelease`. **VS 2015 and earlier are not reported** — neither `vswhere` nor the `Setup\Instances` registry fallback covers them. That fallback engages only when `vswhere.exe` is missing entirely, not per install |
| .NET | `dotnet` is invoked from `PATH`. If it is absent the skill says so instead of hunting for it, and it never reports the `Host:` version as an SDK |
| Screenshot | A **rendering** of captured stdout on the cmd palette — not a real screen capture. There is no window chrome and no console was ever displayed |
| Folder icons | Explorer-**style** icons drawn with GDI+, not the real shell icons extracted from the system, so they do not follow your icon theme |
| Output location | Outside a Copilot session, the output root falls back to the **newest** folder under `~/.copilot/session-state`, which may not be the session you expect. Pass `-OutputRoot` when it matters; the final fallback is `%TEMP%\vs-config-info` |
| Return values | `powershell -File` flattens returned objects to text, so the image scripts also print a machine-readable line such as `[sdk.png] rows=3 verified=True`. Array parameters can only be passed in-process |

### The razor matrix

The one format with real caveats, because it is the only one that builds anything:

- **A matching SDK is required per framework, by major version.** A 9.x SDK can target `net8.0`,
  but the script will not use it that way. Frameworks without a same-major SDK are skipped rather
  than quietly built by a different one — conservative on purpose, since the point of the format is
  to show what each SDK actually produces.
- **`win-x64` self-contained only.** The RID is not configurable, including on arm64.
- **Roughly 100–200 MB per framework**, and it is the only part of the skill that writes outside
  the session folder. It dry-runs unless you pass `-Force`; `-Cleanup` removes the scratch folder.
- **The `-Force` path has never executed on a developer machine here.** It is exercised only by the
  manual `razor-matrix` workflow, which is the only environment with the necessary SDKs. See
  [`test-result.md`](test-result.md).

## Where the CLI looks for skills

Copilot CLI discovers skills from several roots. Any of these works — pick based on who should
get the skill:

| Scope | Location | Use when |
| --- | --- | --- |
| **Personal** | `~/.copilot/skills/` or `~/.agents/skills/` | You want it in every repository you work in |
| **Project** | `.github/skills/`, `.agents/skills/` or `.claude/skills/` | The whole team should get it with a clone |
| **Custom** | Any directory registered with `/skills add` | The checkout already lives somewhere else |

A skill is one folder containing a `SKILL.md`; the name comes from that file's front matter, not
from the folder.

## Install it

### Personal (recommended)

```powershell
git clone https://github.com/cyimperial/vs-config-info.git `
  "$env:USERPROFILE\.copilot\skills\vs-config-info"
```

### Project-wide

Committed alongside the code, so everyone who clones the repository gets it:

```powershell
git clone https://github.com/cyimperial/vs-config-info.git .github\skills\vs-config-info
```

### From an existing checkout

If you have already cloned it somewhere else, register that path instead of copying it:

```text
/skills add C:\src\vs-config-info
```

`/skills add --project <path>` installs into `.github/skills` instead.

## Verify

Three checks, cheapest first.

**1. The files are where the CLI will look.**

```powershell
Get-ChildItem "$env:USERPROFILE\.copilot\skills\vs-config-info" -Name
# .github
# docs
# scripts
# tests
# .gitignore
# LICENSE
# README.md
# SKILL.md
```

`SKILL.md` must sit at the *root* of the skill folder. A nested extra directory — the usual
result of `git clone` without a target path — is the most common reason a skill never loads.

**2. The skill actually works on this machine.**

```powershell
cd "$env:USERPROFILE\.copilot\skills\vs-config-info"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1
```

Exit code `0` means the whole suite passed. This runs entirely offline, writes only to `%TEMP%`,
and needs no test framework. See [`testing.md`](testing.md), and
[`test-result.md`](test-result.md) for what a good run looks like.

**3. Copilot CLI can see it.**

Start `copilot`, then:

```text
/skills list
```

`vs-config-info` should be listed under its source. If you installed it while the CLI was already
running, `/skills reload` picks it up without a restart.

Then try it for real — ask `vs config` or `show me my dotnet setup`, and the launcher appears.

## Execution policy

A default Windows install is set to `Restricted`, which blocks `.ps1` files. Every command in
this repository passes `-ExecutionPolicy Bypass`, which applies to that **process only**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\<Script>.ps1"
```

Nothing needs to be unblocked and no machine policy is changed. Because the scope is the process,
scripts that call sibling scripts in-process inherit it and work without extra flags.

## Updating

```powershell
cd "$env:USERPROFILE\.copilot\skills\vs-config-info"
git pull
```

Then `/skills reload` in a running session. Re-run the test suite after updating — it is the
fastest way to confirm the new revision is healthy on your machine.

## Uninstalling

Delete the folder:

```powershell
Remove-Item "$env:USERPROFILE\.copilot\skills\vs-config-info" -Recurse -Force
```

For a directory registered with `/skills add`, unregister it instead:

```text
/skills remove vs-config-info
```

The skill writes generated PNGs to your Copilot CLI session folder and nothing else, so removal
leaves no state behind. The one exception is the razor matrix, which builds under `%TEMP%` and
only when you pass `-Force`; `-Cleanup` removes that scratch folder.

## Troubleshooting

### The skill never activates

Check `/skills list` first. If it is absent, `SKILL.md` is not at the root of a folder under a
scanned directory. If it is present but never triggers, say `vs config` explicitly — discovery is
driven by the `description` front matter, and a vague prompt may not match it.

### `... cannot be loaded because running scripts is disabled`

A `.ps1` was launched without `-ExecutionPolicy Bypass`. Use the full command form above.

### PowerShell 7

GDI+ moved out of the box in .NET Core, so `System.Drawing` is not available to PowerShell 7
without the `System.Drawing.Common` package. The scripts detect this and tell you both remedies
instead of failing on a cryptic `Add-Type` error. Windows PowerShell 5.1 remains the verified
host, and it is present on every supported version of Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1
```

(`powershell.exe` is 5.1; `pwsh.exe` is 7.)

### No SDKs installed

If a machine has the .NET *runtime* but no SDK, `dotnet --info` still prints a `Host:` version.
The skill will not report that as an SDK — it reports zero SDKs, which is the truth. Formats that
need an SDK, such as the razor matrix, will say so rather than producing an empty result.

### The razor matrix builds nothing

A dry run listing every framework as `SKIP - no matching SDK installed` is correct behaviour, not
a failure — it dry-runs unless you pass `-Force`, and it only builds frameworks with a same-major
SDK. See [Limitations](#the-razor-matrix) and [`scripts.md`](scripts.md).

---

Design rules and repository layout: [`README.md`](README.md).
Script parameters: [`scripts.md`](scripts.md).
