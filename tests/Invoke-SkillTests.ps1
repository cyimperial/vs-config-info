<#
.SYNOPSIS
    Test suite for the vs-config-info skill.

.DESCRIPTION
    Self-contained - deliberately no Pester dependency, so CI needs no module install and the
    suite runs identically on a developer machine and on windows-latest.

    Covers the three defect classes that produced the original audit failures:
      * static defects  - unparseable code, hardcoded user paths, invalid tool parameters
      * helper defects  - free-form version text, filename safety, StrictMode crashes
      * render defects  - clipped labels, wrong sort order, unverified output

.PARAMETER SkipRenderTests
    Skip the GDI+ image tests (useful on a headless host without System.Drawing).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-SkillTests.ps1
#>
[CmdletBinding()]
param([switch]$SkipRenderTests)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$ScriptsRoot = Join-Path $RepoRoot 'scripts'
$TempRoot    = Join-Path $env:TEMP "vsci-tests-$(Get-Date -Format 'yyyyMMddHHmmss')"

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
# $env:TEMP is an 8.3 short path ("C:\Users\<user>~1\...") while the scripts under test
# return long paths. Get-Item expands 8.3; Resolve-Path does not.
$TempRoot = (Get-Item -LiteralPath $TempRoot).FullName

$script:Passed   = 0
$script:Failed   = 0
$script:Skipped  = 0
$script:Failures = @()

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    try {
        & $Body
        $script:Passed++
        Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like 'SKIP::*') {
            $script:Skipped++
            Write-Host ("  SKIP  {0}" -f $Name) -ForegroundColor Yellow
            Write-Host ("        {0}" -f ($_.Exception.Message -replace '^SKIP::', '')) -ForegroundColor DarkGray
            return
        }
        $script:Failed++
        $script:Failures += "$Name :: $($_.Exception.Message)"
        Write-Host ("  FAIL  {0}" -f $Name) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Assert-Skip {
    # Environment-dependent tests must not fail a build. CI runners and developer machines
    # carry different SDK sets - and an SDK can even be uninstalled mid-session.
    param([string]$Reason)
    throw "SKIP::$Reason"
}

function Assert-True {
    param([bool]$Condition, [string]$Message = 'Expected condition to be true')
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = 'Values differ')
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
}

function Assert-Throws {
    param([scriptblock]$Body, [string]$Message = 'Expected an exception', [string[]]$MessageLike)
    $err = $null
    try { & $Body | Out-Null } catch { $err = $_ }
    if (-not $err) { throw $Message }
    foreach ($pattern in $MessageLike) {
        if ($err.Exception.Message -notlike $pattern) {
            throw "$Message - thrown message did not match '$pattern': $($err.Exception.Message)"
        }
    }
}

function Get-ImageSize {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($Path)
    try   { return [pscustomobject]@{ Width = $img.Width; Height = $img.Height } }
    finally { $img.Dispose() }
}

# =============================================================================
Write-Host "`n=== Static checks ===" -ForegroundColor Cyan
# =============================================================================

Test-Case 'every script parses' {
    $bad = @()
    foreach ($file in (Get-ChildItem $ScriptsRoot -Filter *.ps1) + (Get-ChildItem $PSScriptRoot -Filter *.ps1)) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        if ($errors.Count) { $bad += "$($file.Name): $($errors[0].Message)" }
    }
    Assert-True ($bad.Count -eq 0) ("parse errors -> " + ($bad -join '; '))
}

Test-Case 'SKILL.md front matter is well formed' {
    $lines = Get-Content (Join-Path $RepoRoot 'SKILL.md')
    Assert-Equal '---' $lines[0] 'first line must open front matter'
    $close = [array]::IndexOf($lines, '---', 1)
    Assert-True ($close -gt 0) 'front matter is not closed'
    Assert-True ([bool]($lines[1..$close] -match '^name:\s*\S')) 'name is missing'
    Assert-True ([bool]($lines[1..$close] -match '^description:\s*\S')) 'description is missing'
}

Test-Case 'SKILL.md description fits the discovery budget' {
    $desc = Get-Content (Join-Path $RepoRoot 'SKILL.md') | Where-Object { $_ -like 'description:*' } | Select-Object -First 1
    Assert-True ($desc.Length -lt 1024) "description is $($desc.Length) chars"
}

Test-Case 'no hardcoded user profile paths in shipped files (B2 regression)' {
    # docs/audit-*.md and docs/fixes-*.md intentionally quote the old defective paths.
    # Everything else - including this harness and its docs - must stay machine-agnostic.
    $files = @(
        (Join-Path $RepoRoot 'SKILL.md')
        (Join-Path $RepoRoot 'README.md')
        (Join-Path $RepoRoot 'docs\README.md')
        (Join-Path $RepoRoot 'docs\scripts.md')
        (Join-Path $RepoRoot 'docs\testing.md')
    ) + @(Get-ChildItem $ScriptsRoot -Filter *.ps1 | Select-Object -ExpandProperty FullName) `
      + @(Get-ChildItem $PSScriptRoot -Filter *.ps1 | Select-Object -ExpandProperty FullName)

    $hits = Select-String -Path $files -Pattern 'C:\\Users\\[A-Za-z0-9._-]+\\' -ErrorAction SilentlyContinue |
        Where-Object { $_.Line -notmatch '<user>' }
    Assert-True (-not $hits) ("hardcoded path in " + (($hits | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', '))
}

Test-Case 'SKILL.md does not reference non-existent ask_user parameters (B3 regression)' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    Assert-True ($md -notmatch 'allow_freeform') 'allow_freeform is not a real ask_user parameter'
}

Test-Case 'PowerShell blocks inside SKILL.md parse (B1 regression)' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    $bad = 0
    foreach ($m in [regex]::Matches($md, '(?s)```powershell\r?\n(.*?)```')) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($m.Groups[1].Value, [ref]$null, [ref]$errors)
        if ($errors.Count) { $bad++ }
    }
    Assert-Equal 0 $bad 'a documented snippet does not parse'
}

Test-Case 'relative markdown links resolve' {
    $broken = @()
    foreach ($file in Get-ChildItem $RepoRoot -Recurse -Filter *.md | Where-Object { $_.FullName -notmatch '\\\.git\\' }) {
        foreach ($m in [regex]::Matches((Get-Content $file.FullName -Raw), '\]\(([^)#:][^):]*\.md|LICENSE)\)')) {
            if (-not (Test-Path (Join-Path $file.DirectoryName $m.Groups[1].Value))) {
                $broken += "$($file.Name) -> $($m.Groups[1].Value)"
            }
        }
    }
    Assert-True ($broken.Count -eq 0) ("broken links: " + ($broken -join ', '))
}

Test-Case 'helper functions are defined exactly once' {
    $defs = @{}
    foreach ($file in Get-ChildItem $ScriptsRoot -Filter *.ps1) {
        foreach ($m in [regex]::Matches((Get-Content $file.FullName -Raw), '(?m)^function\s+([\w-]+)')) {
            $name = $m.Groups[1].Value
            if (-not $defs.ContainsKey($name)) { $defs[$name] = @() }
            $defs[$name] += $file.Name
        }
    }
    $dupes = @($defs.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    Assert-True ($dupes.Count -eq 0) ("duplicated: " + (($dupes | ForEach-Object { "$($_.Key) in $($_.Value -join '+')" }) -join ', '))
}

# =============================================================================
Write-Host "`n=== Helper unit tests ===" -ForegroundColor Cyan
# =============================================================================

. (Join-Path $ScriptsRoot 'VsConfigInfo.Common.ps1')

Test-Case 'Get-JsonProperty returns a default instead of throwing (StrictMode)' {
    $obj = '{ "runtimeTarget": {} }' | ConvertFrom-Json
    Assert-Equal $null      (Get-JsonProperty $obj 'targets')
    Assert-Equal 'fallback' (Get-JsonProperty $obj 'targets' 'fallback')
}

Test-Case 'Get-JsonProperty survives a vswhere entry with no catalog (P1 regression)' {
    # Visual Studio Build Tools installs can omit `catalog` entirely; the old
    # $_.catalog.productDisplayVersion crashed with PropertyNotFoundStrict.
    $install = '{ "displayName": "Visual Studio Build Tools", "installationVersion": "17.9.1" }' | ConvertFrom-Json
    Assert-Equal $null   (Get-JsonProperty $install 'catalog.productDisplayVersion')
    Assert-Equal '17.9.1' (Get-JsonProperty $install 'installationVersion')
}

Test-Case 'Get-JsonProperty reads a nested path that does exist' {
    $install = '{ "catalog": { "productDisplayVersion": "17.12.4" } }' | ConvertFrom-Json
    Assert-Equal '17.12.4' (Get-JsonProperty $install 'catalog.productDisplayVersion')
}

Test-Case 'direct property access would still throw (proves the test is meaningful)' {
    $obj = '{ "runtimeTarget": {} }' | ConvertFrom-Json
    Assert-Throws { $null = $obj.targets.something } 'expected PropertyNotFoundStrict'
}

Test-Case 'ConvertTo-SortableVersion handles free-form product text (N1 regression)' {
    Assert-Equal ([version]'12023.133') (ConvertTo-SortableVersion 'Insiders [12023.133]')
    Assert-Equal ([version]'0.0')       (ConvertTo-SortableVersion 'no digits here')
    Assert-Equal ([version]'0.0')       (ConvertTo-SortableVersion '')
}

Test-Case 'ConvertTo-SortableVersion orders 9.0.17 before 10.0.9 (N3 regression)' {
    $sorted = @('10.0.9', '8.0.28', '9.0.17', '8.0.30') | Sort-Object { ConvertTo-SortableVersion $_ }
    Assert-Equal '8.0.28,8.0.30,9.0.17,10.0.9' ($sorted -join ',')
}

Test-Case 'ConvertTo-SafeFileNamePart produces a usable filename (N1 regression)' {
    Assert-Equal 'Insiders-12023.133' (ConvertTo-SafeFileNamePart 'Insiders [12023.133]')
    Assert-Equal 'unknown'            (ConvertTo-SafeFileNamePart '')

    $result = ConvertTo-SafeFileNamePart 'a/b\c:d*e?f"g<h>i|j'
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        Assert-True (-not $result.Contains($c)) 'result still contains an invalid character'
    }
}

Test-Case 'Format-JsonIndent normalises indentation and collapses empties (N5 regression)' {
    $out = Format-JsonIndent -Json ('{ "targets": { "a": {}, "b": { "c": "1" } } }' | ConvertFrom-Json | ConvertTo-Json -Depth 8)
    Assert-True ($out -match '"a": \{\}') 'empty object was not collapsed'
    Assert-Equal ([regex]::Matches($out, '\{')).Count ([regex]::Matches($out, '\}')).Count 'braces are unbalanced'
    Assert-True ($out -match '(?m)^  "targets"') 'top-level key is not indented by 2'
}

Test-Case 'Format-JsonIndent does not reformat inside string values' {
    $out = Format-JsonIndent -Json '{"path":"C:\\Program Files\\dotnet, x"}'
    Assert-True ($out -match 'Program Files') 'string content was altered'
    Assert-True ($out -match 'dotnet, x')     'punctuation inside a string was reformatted'
}

Test-Case 'Get-DotnetRootPath resolves to a real folder (Y5 regression)' {
    $root = Get-DotnetRootPath
    Assert-True ([bool]$root) 'no dotnet root resolved'
    Assert-True (Test-Path -LiteralPath $root) "resolved root does not exist: $root"
}

Test-Case 'Get-VsConfigOutputRoot honours an explicit root' {
    $explicit = Join-Path $TempRoot 'explicit-root'
    $result = Get-VsConfigOutputRoot -OutputRoot $explicit
    Assert-True (Test-Path $explicit) 'explicit root was not created'
    Assert-Equal (Get-Item -LiteralPath $explicit).FullName (Get-Item -LiteralPath $result).FullName 'returned a different folder'
}

# --- P4: host compatibility --------------------------------------------------
# Get-VsConfigDrawingPlan is pure, so the PowerShell 7 and non-Windows branches are
# reachable from Windows PowerShell 5.1 - where they would otherwise never execute.

Test-Case 'Drawing plan uses the GAC assembly on Windows PowerShell 5.1 (P4)' {
    $plan = Get-VsConfigDrawingPlan -Edition Desktop -OnWindows $true
    Assert-True $plan.Supported 'Desktop on Windows should be supported'
    Assert-Equal 'System.Drawing' $plan.AssemblyName
    Assert-True (-not $plan.NeedsPackage) 'Desktop must not require a package'
}

Test-Case 'Drawing plan switches to System.Drawing.Common on PowerShell 7 (P4)' {
    $plan = Get-VsConfigDrawingPlan -Edition Core -OnWindows $true
    Assert-True $plan.Supported 'Core on Windows should be supported'
    Assert-Equal 'System.Drawing.Common' $plan.AssemblyName
    Assert-True $plan.NeedsPackage 'Core needs the System.Drawing.Common package'
}

Test-Case 'Drawing plan refuses non-Windows hosts with a reason (P4)' {
    foreach ($edition in 'Desktop', 'Core') {
        $plan = Get-VsConfigDrawingPlan -Edition $edition -OnWindows $false
        Assert-True (-not $plan.Supported) "$edition off Windows should be unsupported"
        Assert-Equal $null $plan.AssemblyName "$edition off Windows should name no assembly"
        Assert-True ($plan.Reason -like '*Windows-only*') "$edition is missing an explanation"
    }
}

Test-Case 'Drawing plan auto-detects the running host (P4)' {
    $plan = Get-VsConfigDrawingPlan
    Assert-True $plan.Supported 'the host running this suite must be supported'
    Assert-True ([bool]$plan.AssemblyName) 'no assembly chosen for the running host'
}

Test-Case 'Initialize-VsConfigDrawing reports both remedies when GDI+ is missing (P4)' {
    # Simulates PowerShell 7 without System.Drawing.Common: the user must get a message they
    # can act on, not a bare "Cannot find assembly" from Add-Type.
    $bogus = [pscustomobject]@{
        Supported    = $true
        AssemblyName = 'VsConfigInfo.NoSuchAssembly'
        NeedsPackage = $true
        Reason       = $null
    }
    Assert-Throws { Initialize-VsConfigDrawing -Plan $bogus -Force } 'expected a load failure' `
        -MessageLike '*Windows PowerShell 5.1*', '*Install-Package System.Drawing.Common*', '*Underlying error:*'
}

Test-Case 'Initialize-VsConfigDrawing refuses an unsupported host (P4)' {
    $unsupported = [pscustomobject]@{
        Supported    = $false
        AssemblyName = $null
        NeedsPackage = $false
        Reason       = 'The vs-config-info skill is Windows-only: test sentinel.'
    }
    Assert-Throws { Initialize-VsConfigDrawing -Plan $unsupported -Force } 'expected a refusal' `
        -MessageLike '*Windows-only*'
}

Test-Case 'GDI+ is loaded once Common is dot-sourced (P4)' {
    Assert-True ([bool]('System.Drawing.Bitmap' -as [type])) 'System.Drawing.Bitmap is not available'
    Initialize-VsConfigDrawing   # must be idempotent
    Assert-True ([bool]('System.Drawing.Bitmap' -as [type])) 're-initialising broke the loaded type'
}

# =============================================================================
Write-Host "`n=== Collector ===" -ForegroundColor Cyan
# =============================================================================

Test-Case 'Get-VsConfigInfo returns the documented shape' {
    $info = & (Join-Path $ScriptsRoot 'Get-VsConfigInfo.ps1')
    foreach ($p in 'Timestamp','Machine','User','DotnetFound','DotnetRoot','SdkVersion','SdkCount','InstalledSdks','DotnetInfo','VisualStudio','Notes') {
        Assert-True ([bool]$info.PSObject.Properties[$p]) "missing property: $p"
    }
    if ($info.DotnetFound) {
        # "Host:" is present whether or not an SDK is installed; "Runtime Environment" is not.
        Assert-True ($info.DotnetInfo -match '(?m)^Host:') 'dotnet --info output looks wrong'
    }
}

Test-Case 'Get-VsConfigInfo never reports the Host version as an SDK version' {
    # Regression: with no SDK installed, `dotnet --info` starts at "Host:" and the old
    # ^Version: match returned the host version (e.g. 8.0.30) as SdkVersion - inventing an
    # SDK the machine does not have, which the skill explicitly forbids.
    $info = & (Join-Path $ScriptsRoot 'Get-VsConfigInfo.ps1')
    if (-not $info.DotnetFound) { Assert-Skip 'dotnet is not installed' }

    if ($info.SdkCount -eq 0) {
        Assert-Equal $null $info.SdkVersion 'reported an SDK version with zero SDKs installed'
        Assert-True ([bool]($info.Notes -match 'No .NET SDK is installed')) 'missing the no-SDK note'
    }
    else {
        Assert-True ([bool]$info.SdkVersion) 'SDK installed but no version reported'
        Assert-True ([bool]($info.InstalledSdks -match [regex]::Escape($info.SdkVersion))) `
            'active SDK version is not among the installed SDKs'
    }
}

Test-Case 'Get-VsConfigInfo emits valid JSON' {
    $json = & (Join-Path $ScriptsRoot 'Get-VsConfigInfo.ps1') -AsJson | Out-String
    $parsed = $json | ConvertFrom-Json
    Assert-True ([bool]$parsed.PSObject.Properties['Timestamp']) 'JSON is missing Timestamp'
}

# =============================================================================
if ($SkipRenderTests) {
    Write-Host "`n=== Renderers skipped ===" -ForegroundColor Yellow
}
else {

Write-Host "`n=== Renderers ===" -ForegroundColor Cyan

Test-Case 'New-CmdScreenshot writes a valid PNG' {
    $path = Join-Path $TempRoot 'shot.png'
    $r = & (Join-Path $ScriptsRoot 'New-CmdScreenshot.ps1') -Command 'dotnet --info' -OutputPath $path
    Assert-True (Test-Path $path) 'no file written'
    $size = Get-ImageSize $path
    Assert-True ($size.Width -gt 200 -and $size.Height -gt 100) "implausible size $($size.Width)x$($size.Height)"
    Assert-True ($r.LineCount -gt 5) 'suspiciously few lines captured'
}

Test-Case 'New-FolderIconImage verifies its own rows against the filesystem' {
    $sdk = Join-Path (Get-DotnetRootPath) 'sdk'
    if (-not (Test-Path -LiteralPath $sdk)) { Assert-Skip "no SDK folder at $sdk" }

    $path = Join-Path $TempRoot 'sdk.png'
    $r = & (Join-Path $ScriptsRoot 'New-FolderIconImage.ps1') -Root $sdk -OutputPath $path

    Assert-True $r.Verified 'script reported Verified = false'
    $actual = @(Get-ChildItem -LiteralPath $sdk -Directory | Select-Object -ExpandProperty Name)
    Assert-Equal $actual.Count $r.RowCount 'row count does not match directory count'
    Assert-True (-not (Compare-Object $actual $r.Labels)) 'labels do not match directory names'
}

Test-Case 'New-FolderIconImage renders long labels without clipping (B1/Y1 regression)' {
    # The original grid-style snippet clipped "10.0.400-preview.0.26322.102" to "1".
    $fake = Join-Path $TempRoot 'fake-sdk'
    $long = '10.0.400-preview.0.26322.102'
    New-Item -ItemType Directory -Path (Join-Path $fake $long) -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fake '9.0.17') -Force | Out-Null

    $path = Join-Path $TempRoot 'fake-sdk.png'
    $r = & (Join-Path $ScriptsRoot 'New-FolderIconImage.ps1') -Root $fake -OutputPath $path
    Assert-True $r.Verified 'verification failed'
    Assert-True ($r.Labels -contains $long) 'long label missing from output'

    # The bitmap must be wide enough to actually contain the drawn text.
    Add-Type -AssemblyName System.Drawing
    $bmp  = [System.Drawing.Bitmap]::new(1, 1)
    $g    = [System.Drawing.Graphics]::FromImage($bmp)
    $font = [System.Drawing.Font]::new('Segoe UI', 11)
    try     { $textWidth = $g.MeasureString($long, $font).Width }
    finally { $font.Dispose(); $g.Dispose(); $bmp.Dispose() }

    $size = Get-ImageSize $path
    Assert-True ($size.Width -ge (48 + $textWidth)) "image width $($size.Width) cannot fit icon + label ($textWidth)"
}

Test-Case 'New-FolderIconImage sorts rows by version, not string (N3 regression)' {
    $fake = Join-Path $TempRoot 'fake-sort'
    foreach ($v in '10.0.9','8.0.28','9.0.17') {
        New-Item -ItemType Directory -Path (Join-Path $fake $v) -Force | Out-Null
    }
    $r = & (Join-Path $ScriptsRoot 'New-FolderIconImage.ps1') -Root $fake -OutputPath (Join-Path $TempRoot 'fake-sort.png')
    Assert-Equal '8.0.28,9.0.17,10.0.9' ($r.Labels -join ',')
}

Test-Case 'New-FolderIconImage handles a missing root without throwing' {
    $path = Join-Path $TempRoot 'missing.png'
    $r = & (Join-Path $ScriptsRoot 'New-FolderIconImage.ps1') -Root (Join-Path $TempRoot 'does-not-exist') -OutputPath $path
    Assert-Equal 0 $r.RowCount 'expected zero rows'
    Assert-True (Test-Path $path) 'no placeholder image written'
    Assert-True ($r.Message -like 'Path not found:*') 'missing-root message not reported'
}

Test-Case 'New-JsonSnippetImage stacks every snippet it is given' {
    $snips = @(
        '{ "targets": { ".NETCoreApp,Version=v10.0": {} } }'
        '{ "targets": { ".NETCoreApp,Version=v9.0": {} } }'
        '{ "targets": { ".NETCoreApp,Version=v8.0": {} } }'
    ) | ForEach-Object { $_ | ConvertFrom-Json | ConvertTo-Json -Depth 8 }

    $path = Join-Path $TempRoot 'matrix.png'
    $r = & (Join-Path $ScriptsRoot 'New-JsonSnippetImage.ps1') -Snippet $snips -OutputPath $path
    Assert-Equal 3 $r.SnippetCount 'wrong snippet count'
    Assert-True (Test-Path $path) 'no file written'
    Assert-True ((Get-ImageSize $path).Height -gt 100) 'image too short to hold three snippets'
}

Test-Case 'New-RazorMatrix dry run creates nothing and never throws (B4 regression)' {
    # A dry run must report a plan on any machine, including one with no SDK at all.
    $work = Join-Path $TempRoot 'razor-workroot'
    $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work
    Assert-True $r.DryRun 'dry run flag not set'
    Assert-True (-not (Test-Path $work)) 'dry run created the work root'
    Assert-Equal $null $r.Path 'dry run reported an output path'
    Assert-True ([bool]$r.PSObject.Properties['Plan']) 'dry run did not report a plan'
    Assert-True ($r.Plan.Count -ge 1) 'plan is empty'
}

Test-Case 'New-RazorMatrix refuses to build when no requested framework has an SDK (B4 regression)' {
    # -Force is required to reach the build path; it must still bail out before creating
    # anything when the requested frameworks are not installed.
    $work = Join-Path $TempRoot 'razor-none'
    Assert-Throws {
        & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -Framework 'net99.0','net98.0' -WorkRoot $work -Force
    } 'expected a throw when no SDK matches'
    Assert-True (-not (Test-Path $work)) 'work root was created despite the failure'
}

}

# =============================================================================
Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host ("  Passed: {0}   Failed: {1}   Skipped: {2}" -f $script:Passed, $script:Failed, $script:Skipped) -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
Write-Host "=================================" -ForegroundColor Cyan

if ($script:Failed) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

exit 0
