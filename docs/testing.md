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
| Helper unit tests | 11 | `Get-JsonProperty` returns a default instead of throwing; `ConvertTo-SortableVersion` orders `9.0.17` before `10.0.9`; `Format-JsonIndent` normalises indentation without touching string values |
| Collector | 3 | `Get-VsConfigInfo` returns the documented shape, emits valid JSON, and never reports the `Host:` version as an SDK version |
| Renderers | 8 | Each image script writes a plausible PNG; long labels are not clipped; a missing root yields a placeholder rather than an exception; the razor dry run creates nothing |

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
  Passed: 29   Failed: 0   Skipped: 1
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
