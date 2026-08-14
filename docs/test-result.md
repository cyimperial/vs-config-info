# Test results

The last full run of `tests\Invoke-SkillTests.ps1`, recorded verbatim so that a fresh clone has
something concrete to compare against.

## Latest run

**2026-08-15 — 39 passed, 0 failed, 1 skipped, exit code `0`, 3.5 seconds.**

| | |
| --- | --- |
| OS | Windows 11 Enterprise, build 10.0.26200 |
| Host | Windows PowerShell 5.1.26100.8875 (`powershell.exe`) |
| Execution policy | `Undefined` at every scope — the effective default, `Restricted` |
| .NET | Host `8.0.30` (win-x64), **no SDKs installed** |
| Copilot CLI | 1.0.80 |
| Command | `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1` |

Only user profile paths have been replaced with `<user>`; nothing else is edited.

```text
=== Static checks ===
  PASS  every script parses
  PASS  SKILL.md front matter is well formed
  PASS  SKILL.md description fits the discovery budget
  PASS  SKILL.md stays lean (P5)
  PASS  no hardcoded user profile paths in shipped files (B2 regression)
  PASS  SKILL.md does not reference non-existent ask_user parameters (B3 regression)
  PASS  PowerShell blocks inside SKILL.md parse (B1 regression)
  PASS  PowerShell inside the CI workflows parses (B1 regression, new file type)
  PASS  the expensive razor build is opt-in only (B4 regression)
  PASS  relative markdown links resolve
  PASS  helper functions are defined exactly once

=== Helper unit tests ===
  PASS  Get-JsonProperty returns a default instead of throwing (StrictMode)
  PASS  Get-JsonProperty survives a vswhere entry with no catalog (P1 regression)
  PASS  Get-JsonProperty reads a nested path that does exist
  PASS  direct property access would still throw (proves the test is meaningful)
  PASS  ConvertTo-SortableVersion handles free-form product text (N1 regression)
  PASS  ConvertTo-SortableVersion orders 9.0.17 before 10.0.9 (N3 regression)
  PASS  ConvertTo-SafeFileNamePart produces a usable filename (N1 regression)
  PASS  Format-JsonIndent normalises indentation and collapses empties (N5 regression)
  PASS  Format-JsonIndent does not reformat inside string values
  PASS  Get-DotnetRootPath resolves to a real folder (Y5 regression)
  PASS  Get-VsConfigOutputRoot honours an explicit root
  PASS  Drawing plan uses the GAC assembly on Windows PowerShell 5.1 (P4)
  PASS  Drawing plan switches to System.Drawing.Common on PowerShell 7 (P4)
  PASS  Drawing plan refuses non-Windows hosts with a reason (P4)
  PASS  Drawing plan auto-detects the running host (P4)
  PASS  Initialize-VsConfigDrawing reports both remedies when GDI+ is missing (P4)
  PASS  Initialize-VsConfigDrawing refuses an unsupported host (P4)
  PASS  GDI+ is loaded once Common is dot-sourced (P4)

=== Collector ===
  PASS  Get-VsConfigInfo returns the documented shape
  PASS  Get-VsConfigInfo never reports the Host version as an SDK version
  PASS  Get-VsConfigInfo emits valid JSON

=== Renderers ===
  PASS  New-CmdScreenshot writes a valid PNG
  SKIP  New-FolderIconImage verifies its own rows against the filesystem
        no SDK folder at C:\Program Files\dotnet\sdk
[fake-sdk.png] rows=2 verified=True labels=9.0.17, 10.0.400-preview.0.26322.102
  PASS  New-FolderIconImage renders long labels without clipping (B1/Y1 regression)
[fake-sort.png] rows=3 verified=True labels=8.0.28, 9.0.17, 10.0.9
  PASS  New-FolderIconImage sorts rows by version, not string (N3 regression)
[missing.png] rows=0 verified=True note=Path not found: C:\Users\<user>\AppData\Local\Temp\vsci-tests-20260815010016\does-not-exist
  PASS  New-FolderIconImage handles a missing root without throwing
[matrix.png] snippets=3 lines=15
  PASS  New-JsonSnippetImage stacks every snippet it is given
Razor matrix plan (work root: C:\Users\<user>\AppData\Local\Temp\vsci-tests-20260815010016\razor-workroot)
  net10.0   SKIP - no matching SDK installed
  net9.0    SKIP - no matching SDK installed
  net8.0    SKIP - no matching SDK installed

Nothing to build - none of the requested frameworks have a matching SDK installed.
  PASS  New-RazorMatrix dry run creates nothing and never throws (B4 regression)
Razor matrix plan (work root: C:\Users\<user>\AppData\Local\Temp\vsci-tests-20260815010016\razor-none)
  net99.0   SKIP - no matching SDK installed
  net98.0   SKIP - no matching SDK installed
  PASS  New-RazorMatrix refuses to build when no requested framework has an SDK (B4 regression)

=================================
  Passed: 39   Failed: 0   Skipped: 1
=================================
```

## Breakdown

| Group | Tests | Passed | Skipped |
| --- | ---: | ---: | ---: |
| Static checks | 11 | 11 | 0 |
| Helper unit tests | 18 | 18 | 0 |
| Collector | 3 | 3 | 0 |
| Renderers | 8 | 7 | 1 |
| **Total** | **40** | **39** | **1** |

The interleaved `[fake-sdk.png] rows=2 verified=True ...` lines are not test output — they are the
renderers' own stdout. The image scripts print what they drew because `powershell -File` flattens
returned objects to text, so a caller cannot rely on the returned hashtable. That line *is* the
machine-readable result.

## The one skip

```
  SKIP  New-FolderIconImage verifies its own rows against the filesystem
        no SDK folder at C:\Program Files\dotnet\sdk
```

That test compares the rendered rows against the real `<dotnet root>\sdk` directory. This machine
has the .NET 8 runtime but no SDK, so the folder does not exist and there is nothing to compare.
The test declares that honestly instead of passing vacuously — **a skip is not a pass**, which is
why the summary line counts it separately. On a machine with an SDK installed, and on the CI
runners, it executes for real.

The same missing SDK is why every razor framework reports `SKIP - no matching SDK installed`. Both
are environment facts, not defects.

## What this run does not prove

| Path | Status | Where it is covered |
| --- | --- | --- |
| Razor build with `-Force` | Never executed | The manual `razor-matrix` workflow — it is the only environment with the required SDKs |
| PowerShell 7 GDI+ | Decision tested, effect not | `Get-VsConfigDrawingPlan` is pure, so the branch is asserted from 5.1 |
| Non-Windows refusal | Decision tested, effect not | Same — the plan returns `Supported = False` with a reason |
| Folder-icon row verification | Skipped here | Runs on CI, where SDKs are installed |

These are stated rather than glossed over, because the value of a green run is exactly the set of
claims it actually supports. See [`testing.md`](testing.md) for why the decision is split from the
effect.

## Reproduce it

```powershell
cd "$env:USERPROFILE\.copilot\skills\vs-config-info"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1
```

No test framework to install, no network access, and all output confined to a per-run folder under
`%TEMP%` that is deleted afterwards. Failures are listed again at the end of the run, and the exit
code is non-zero if any test failed.

Your numbers will differ from the table above where your machine does: with SDKs installed, expect
40 passed and 0 skipped.

## Continuous integration

Every push and pull request runs the same suite on `windows-latest` via
[`test.yml`](../.github/workflows/test.yml). CI runners ship with .NET SDKs, so the tests that skip
on a bare machine execute there — the two environments cover each other.

Current status is on the badge in the [repository README](../README.md).
