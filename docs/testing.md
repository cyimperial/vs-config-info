# Testing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tests\Invoke-SkillTests.ps1"
```

Exit code `0` means every test passed. Failures are listed again at the end of the run.

The suite has **no external dependencies** — no Pester, no modules to install. It is a single
self-contained script so that a fresh clone on a stock Windows box can verify itself.

## What it covers

| Group | Tests | Examples |
| --- | --- | --- |
| Static checks | 8 | Every script parses; front matter is well formed; the `description` fits the discovery budget; no hardcoded user profile paths; every PowerShell block inside `SKILL.md` parses; relative markdown links resolve; no helper is defined twice |
| Helper unit tests | 18 | `Get-JsonProperty` returns a default instead of throwing; `ConvertTo-SortableVersion` orders `9.0.17` before `10.0.9`; `Format-JsonIndent` normalises indentation without touching string values; the drawing plan picks the right assembly per host |
| Collector | 3 | `Get-VsConfigInfo` returns the documented shape, emits valid JSON, and never reports the `Host:` version as an SDK version |
| Renderers | 8 | Each image script writes a plausible PNG; long labels are not clipped; a missing root yields a placeholder rather than an exception; the razor dry run creates nothing |

## Testing branches that cannot run here

Two code paths matter but are unreachable on a Windows PowerShell 5.1 box: the PowerShell 7
GDI+ path and the non-Windows refusal. Rather than leave them untested, the *decision* is split
from the *effect* — `Get-VsConfigDrawingPlan` is pure and takes `-Edition` / `-OnWindows`, so
every branch is reachable from 5.1:

```powershell
Get-VsConfigDrawingPlan -Edition Core -OnWindows $true    # -> System.Drawing.Common
Get-VsConfigDrawingPlan -Edition Core -OnWindows $false   # -> Supported = False
```

The failure *message* is covered too: `Initialize-VsConfigDrawing -Plan <bogus> -Force` forces a
real load failure and the test asserts the text names both remedies. This is a deliberate
pattern — where an environment cannot be reproduced, make the logic injectable instead of
declaring it untestable.

Every blocker and every bug found during the rewrite has a named regression test, tagged with
its ID from [`fixes-2026-08-14.md`](fixes-2026-08-14.md) — for example
`PowerShell blocks inside SKILL.md parse (B1 regression)`.

## Environment-dependent tests

Some assertions need a specific machine state — the folder-icon test compares rendered rows
against the real `<dotnet root>\sdk` directory, which does not exist on a machine with only a
host runtime installed. Those tests call `Assert-Skip` and report `SKIP` rather than failing:

```
  SKIP  New-FolderIconImage verifies its own rows against the filesystem
        no SDK folder at C:\Program Files\dotnet\sdk
```

A skip is not a pass. The summary line reports skips separately so they stay visible:

```
  Passed: 36   Failed: 0   Skipped: 1
```

Tests are written to skip only when the *environment* cannot support them, never to paper over
a product failure.

## Isolation

The suite writes exclusively to a per-run folder under `%TEMP%` (`vsci-tests-<timestamp>`) and
removes it afterwards. It never builds, never touches `Program Files`, and never runs the razor
matrix with `-Force`.

> `%TEMP%` resolves to an 8.3 short path (`C:\Users\<user>~1\...`) while the scripts under test
> return long paths. The harness canonicalises its temp root with `(Get-Item ...).FullName`,
> which expands 8.3 — `Resolve-Path` does not.

## Continuous integration

[`.github/workflows/test.yml`](../.github/workflows/test.yml) runs the suite on
`windows-latest` for every push to `main`, every pull request, and on demand. Windows is the
only meaningful target: the skill depends on `System.Drawing`/GDI+, `cmd`, `vswhere` and
Explorer-style icons.

CI runners ship with .NET SDKs installed, so the SDK-dependent tests that skip on a bare
machine execute for real there.
