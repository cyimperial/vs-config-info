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

It only builds frameworks you have a matching SDK for, and it dry-runs unless you pass `-Force`.
A dry run listing every framework as `SKIP - no matching SDK installed` is correct behaviour, not
a failure. See [`scripts.md`](scripts.md).

---

Design rules and repository layout: [`README.md`](README.md).
Script parameters: [`scripts.md`](scripts.md).
