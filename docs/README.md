# vs-config-info documentation

| Document | What it covers |
| --- | --- |
| [`scripts.md`](scripts.md) | Parameter reference for everything in `scripts/` |
| [`testing.md`](testing.md) | How to run the test suite, what it covers, and how CI runs it |
| [`audit-2026-08-14.md`](audit-2026-08-14.md) | The skill review that triggered the rewrite, with scoring rubric |
| [`fixes-2026-08-14.md`](fixes-2026-08-14.md) | Every issue found and how it was fixed, with before/after |

## Design rules

These are the invariants the skill is expected to keep. Breaking one is a regression.

1. **No rendering code inline in `SKILL.md`.** Drawing logic lives in `scripts/` where it can
   be parsed, executed and verified. Untested inline snippets were the root cause of the
   original clipped-label and syntax-error defects.
2. **No hardcoded user profile paths.** Output locations resolve through
   `Get-VsConfigOutputRoot`; the dotnet install root resolves through `Get-DotnetRootPath`
   (which honours `DOTNET_ROOT`). The skill is published for other people to clone.
3. **Never fabricate configuration values.** If `dotnet` or `vswhere` is absent, report that
   fact. Version strings are reproduced verbatim, including free-form text such as
   `Insiders [12023.133]`.
4. **Destructive work is opt-in.** Anything that writes outside the session folder dry-runs by
   default and requires explicit confirmation plus `-Force`.
5. **Assert what you rendered.** Image scripts verify their output (for example, folder-icon
   row count versus actual directory count) and surface a `Verified` flag.
6. **Every fixed defect keeps a test.** `tests/Invoke-SkillTests.ps1` carries a named regression
   case for each blocker and each bug found while testing. See [`testing.md`](testing.md).

## Running the scripts

Execution policy on a default Windows install is `Restricted`, which blocks `.ps1` files even
when they are launched in-process. Always invoke through:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\<Script>.ps1"
```

`-ExecutionPolicy Bypass` sets the **process** scope, so scripts that call sibling scripts
in-process (such as `New-RazorMatrix.ps1` calling `New-JsonSnippetImage.ps1`) work without
further flags.
