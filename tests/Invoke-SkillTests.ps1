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

function Get-WorkflowPowerShellBlock {
    <#
        Extracts the body of every `run: |` block belonging to a PowerShell step in a workflow
        file. Deliberately hand-rolled: PowerShell 5.1 has no YAML parser, and adding a module
        dependency would defeat the point of a self-contained suite.
    #>
    param([string]$Path)

    $lines  = @(Get-Content -LiteralPath $Path)
    $shell  = $null
    $blocks = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s*-\s+(name|uses):') { $shell = $null }
        if ($line -match '^\s*shell:\s*(\S+)\s*$') { $shell = $Matches[1] }

        if ($line -match '^(\s*)run:\s*\|\s*$') {
            $indent = $Matches[1].Length
            $body   = @()

            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $next = $lines[$j]
                if ($next.Trim() -eq '') { $body += ''; continue }
                $nextIndent = ($next -replace '\S.*$').Length
                if ($nextIndent -le $indent) { break }
                $body += $next.Substring($indent + 2)
            }

            if ($shell -in 'powershell', 'pwsh') {
                $blocks += [pscustomobject]@{
                    File   = Split-Path $Path -Leaf
                    Line   = $i + 1
                    Script = ($body -join "`n")
                }
            }
        }
    }

    return $blocks
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

Test-Case 'SKILL.md stays lean (P5)' {
    # The whole file is loaded into context every time the skill activates, so it routes and
    # delegates detail to docs/ rather than explaining how the scripts work internally.
    $file  = Get-Item (Join-Path $RepoRoot 'SKILL.md')
    $lines = @(Get-Content $file.FullName).Count
    Assert-True ($lines -le 200) "SKILL.md has grown to $lines lines (budget 200)"
    Assert-True ($file.Length -le 10240) "SKILL.md has grown to $($file.Length) bytes (budget 10 KB)"
}

Test-Case 'no hardcoded user profile paths in shipped files (B2 regression)' {
    # docs/audit-*.md and docs/fixes-*.md intentionally quote the old defective paths.
    # Everything else - including this harness and its docs - must stay machine-agnostic.
    $files = @(
        (Join-Path $RepoRoot 'SKILL.md')
        (Join-Path $RepoRoot 'README.md')
        (Join-Path $RepoRoot 'docs\README.md')
        (Join-Path $RepoRoot 'docs\installation.md')
        (Join-Path $RepoRoot 'docs\scripts.md')
        (Join-Path $RepoRoot 'docs\testing.md')
        (Join-Path $RepoRoot 'docs\test-result.md')
    ) + @(Get-ChildItem $ScriptsRoot -Filter *.ps1 | Select-Object -ExpandProperty FullName) `
      + @(Get-ChildItem $PSScriptRoot -Filter *.ps1 | Select-Object -ExpandProperty FullName)

    $hits = Select-String -Path $files -Pattern 'C:\\Users\\[A-Za-z0-9._-]+\\' -ErrorAction SilentlyContinue |
        Where-Object { $_.Line -notmatch '<user>' }
    Assert-True (-not $hits) ("hardcoded path in " + (($hits | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', '))
}

Test-Case 'SKILL.md does not reference non-existent ask_user parameters (B3 regression)' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    Assert-True ($md -notmatch 'allow_freeform') 'allow_freeform is not a real ask_user parameter'
    Assert-True ($md -notmatch 'accepts only\s+`question` and `choices`') 'obsolete ask_user schema'
    Assert-True ($md -match '`message`.*`requestedSchema`') 'launcher must use the available ask_user schema'
}

Test-Case 'all eight direct formats map to existing workflows and have usage examples' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    $readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
    $formats = [ordered]@{
        summary = @('Text summary', 'Get-VsConfigInfo.ps1')
        doctor = @('Doctor mode', 'Get-VsConfigInfo.ps1')
        screenshot = @('Screenshot', 'New-CmdScreenshot.ps1')
        both = @('Both', 'New-CmdScreenshot.ps1', 'Get-VsConfigInfo.ps1')
        raw = @('Raw output only', 'Get-VsConfigInfo.ps1')
        folders = @('Folder icons', 'Get-VsConfigInfo.ps1', 'New-FolderIconImage.ps1')
        all = @('All-in-one', 'New-RazorMatrix.ps1')
        razor = @('Razor matrix', 'New-RazorMatrix.ps1')
    }
    $rows = [regex]::Matches($md, '(?m)^\| `(\w+)` \| ([^|]+) \| ([^|\r\n]+) \|')
    Assert-Equal $formats.Count $rows.Count 'format table must contain exactly eight mappings'
    foreach ($format in $formats.Keys) {
        $row = @($rows | Where-Object { $_.Groups[1].Value -ceq $format })
        Assert-Equal 1 $row.Count "missing or duplicate mapping for $format"
        Assert-Equal $formats[$format][0] $row[0].Groups[2].Value.Trim() "wrong workflow for $format"
        foreach ($script in $formats[$format] | Select-Object -Skip 1) {
            Assert-True ($row[0].Groups[3].Value.Contains($script)) "missing script $script for $format"
            Assert-True (Test-Path (Join-Path $ScriptsRoot $script)) "mapped script does not exist: $script"
        }
        Assert-True ($readme.Contains("/vs-config-info $format``")) "missing command example for $format"
    }
}

Test-Case 'direct format routing precedes collection and rejects unknown arguments' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    $selection = [regex]::Match($md, '(?s)### 1\. Select a format before running scripts(.*?)### 2\. Collect once, reuse')
    Assert-True $selection.Success 'format routing must happen before collection'
    $routing = $selection.Groups[1].Value
    Assert-True ($routing -match 'trim whitespace.*case-insensitively') 'argument normalization is missing'
    Assert-True ($routing -match 'recognized format skips the launcher') 'direct format must skip the launcher'
    Assert-True ($routing -match '(?s)unknown format \(including extra tokens\).*?list the supported choices.*?stop without\s+running any scripts or showing the launcher') 'invalid arguments must stop with choices'
    Assert-True ($routing -match 'Do not forward arguments as script parameters or commands') 'arguments must not become script commands'
}

Test-Case 'launcher remains interactive and never silently defaults when input is unavailable' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    Assert-True ($md -match 'With no format, show the existing launcher') 'no-argument launcher is missing'
    Assert-True ($md -match '(?s)Preserve natural-language format requests.*?without showing the launcher') 'natural-language selection regressed'
    Assert-True ($md -match '(?s)interactive input is unavailable.*?Choose a format directly: /vs-config-info <format>.*?Stop without running scripts; never silently choose text summary') 'non-interactive fallback must explain direct invocation and stop'
    $choices = [regex]::Matches($md, '(?m)^  [1-9]\. `')
    Assert-Equal 9 $choices.Count 'existing launcher must retain its nine choices'
    Assert-True ($md -match 'On `Cancel`, acknowledge and stop') 'cancel must still stop'
}

Test-Case 'direct all and razor formats retain dry-run and explicit build confirmation' {
    $md = Get-Content (Join-Path $RepoRoot 'SKILL.md') -Raw
    $all = [regex]::Match($md, '(?s)\*\*All-in-one\*\*(.*?)\*\*Razor matrix\*\*').Groups[1].Value
    Assert-True ($all -match '(?s)dry-run and explicit confirmation.*?/vs-config-info all') 'all must use the Razor confirmation workflow'
    Assert-True ($all -match '(?s)declined or unavailable.*?produce the other four.*?omitted the razor matrix') 'all must omit unconfirmed builds'
    $razor = [regex]::Match($md, '(?s)\*\*Razor matrix\*\*(.*?)## Output style').Groups[1].Value
    Assert-True ($razor -match '(?s)1\. Dry run and show the plan.*?2\. Obtain explicit build confirmation.*?3\. Only after affirmative confirmation re-run with `-Force`') 'dry run, confirmation and build must remain ordered'
    Assert-True ($razor -match '/vs-config-info razor` and `/vs-config-info all` select formats, not build consent') 'format arguments must not authorize builds'
    Assert-True ($razor -match '(?s)confirmation is declined or unavailable, do not build or pass `-Force`.*?interactive confirmation is required') 'unavailable confirmation must not authorize builds'
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

Test-Case 'PowerShell inside the CI workflows parses (B1 regression, new file type)' {
    # The workflows embed inline PowerShell, which is exactly the defect class B1 came from.
    # A broken CI script would otherwise only be discovered on a manual dispatch.
    $workflowDir = Join-Path $RepoRoot '.github\workflows'
    Assert-True (Test-Path $workflowDir) 'no workflows folder'

    $blocks = @()
    foreach ($wf in Get-ChildItem $workflowDir -Filter *.yml) {
        $blocks += Get-WorkflowPowerShellBlock -Path $wf.FullName
    }
    Assert-True ($blocks.Count -ge 2) "expected inline PowerShell steps, found $($blocks.Count)"

    $bad = @()
    foreach ($b in $blocks) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($b.Script, [ref]$null, [ref]$errors)
        if ($errors.Count) { $bad += "$($b.File):$($b.Line) - $($errors[0].Message)" }
    }
    Assert-True ($bad.Count -eq 0) ("unparseable workflow step: " + ($bad -join '; '))
}

Test-Case 'the expensive razor build is opt-in only (B4 regression)' {
    # It must never be reachable from push or pull_request.
    $razor = Join-Path $RepoRoot '.github\workflows\razor-matrix.yml'
    Assert-True (Test-Path $razor) 'razor-matrix workflow is missing'

    $yaml = Get-Content $razor -Raw
    Assert-True ($yaml -match '(?m)^\s*workflow_dispatch:') 'not dispatch-triggered'
    Assert-True ($yaml -notmatch '(?m)^\s{2}(push|pull_request):') 'the razor build is wired to push or pull_request'
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

Write-Host "`n=== Razor matrix (fake dotnet; no builds or downloads) ===" -ForegroundColor Cyan

function Invoke-RazorFixture {
    param([string]$Mode = 'success', [scriptblock]$Body)
    $bin = Join-Path $TempRoot 'fake dotnet'
    $exe = Join-Path $bin 'dotnet.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
public class RazorTestDotnet {
    public static int Main(string[] args) {
        string mode = Environment.GetEnvironmentVariable("VSCI_RAZOR_TEST_MODE");
        if (args[0] == "--list-sdks") {
            if (mode != "no-sdk") Console.WriteLine("10.0.100 [fake sdk]");
            return 0;
        }
        string tfm = new DirectoryInfo(Environment.CurrentDirectory).Name;
        Console.WriteLine("fixture stdout: " + String.Join(" ", args));
        if (mode == "all-fail" || (mode == "mixed" &&
            ((tfm == "net11.0" && args[0] == "new") ||
             (tfm == "net10.0" && args[0] == "publish")))) {
            Console.Error.WriteLine("fixture stderr: unsupported target/template or restore failed for " + tfm);
            return 17;
        }
        if (args[0] == "new") {
            int outputIndex = Array.IndexOf(args, "--output");
            string projectDirectory = outputIndex >= 0 ? args[outputIndex + 1] : "razor";
            Directory.CreateDirectory(projectDirectory);
            File.WriteAllText(Path.Combine(projectDirectory, "razor.csproj"), "<Project />");
        }
        if (args[0] == "publish") {
            if (!File.Exists("razor.csproj")) {
                Console.Error.WriteLine("MSB1003: No project in the publish working directory.");
                return 1;
            }
            string output = args[Array.IndexOf(args, "-o") + 1];
            Directory.CreateDirectory(output);
            string json = "{\"targets\":{\".NETCoreApp,Version=v" + tfm.Substring(3) +
                "\":{},\".NETCoreApp,Version=v" + tfm.Substring(3) +
                "/win-x64\":{\"runtimepack.Microsoft.NETCore.App.Runtime.win-x64/10.0.1\":{\"runtime\":{\"fixture.dll\":{}}}}}}";
            if (mode == "deps-errors") {
                if (tfm == "net11.0") json = "{ invalid json";
                if (tfm == "net10.0") return 0;
                if (tfm == "net9.0") json = "{}";
            }
            File.WriteAllText(Path.Combine(output, "razor.deps.json"), json);
        }
        return 0;
    }
}
'@
    }
    $oldPath = $env:PATH
    $oldMode = $env:VSCI_RAZOR_TEST_MODE
    try {
        $env:PATH = $bin + ';' + $oldPath
        $env:VSCI_RAZOR_TEST_MODE = $Mode
        & $Body
    }
    finally {
        $env:PATH = $oldPath
        $env:VSCI_RAZOR_TEST_MODE = $oldMode
    }
}

Test-Case 'Razor dry run plans net11 through net8 with only a net10 SDK and creates nothing' {
    Invoke-RazorFixture -Body {
        $work = Join-Path $TempRoot 'razor dry work'
        $output = Join-Path $TempRoot 'razor dry output'
        $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work -OutputRoot $output
        Assert-True $r.DryRun 'dry run flag not set'
        Assert-Equal 'net11.0,net10.0,net9.0,net8.0' ($r.Plan.Framework -join ',')
        Assert-Equal 4 @($r.Plan | Where-Object Supported).Count 'a same-major SDK must not be required'
        Assert-True (-not (Test-Path $work)) 'dry run created the work root'
        Assert-True (-not (Test-Path $output)) 'dry run created the output root'
        Assert-Equal $null $r.Path 'dry run reported an output path'
    }
}

Test-Case 'Razor runtime-only host reports the missing SDK and cannot build' {
    Invoke-RazorFixture -Mode 'no-sdk' -Body {
        $work = Join-Path $TempRoot 'razor-no-sdk'
        $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work
        Assert-Equal 0 @($r.Plan | Where-Object Supported).Count
        Assert-True ($r.Plan[0].Reason -like '*runtime alone*') 'missing SDK explanation'
        Assert-Throws {
            & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work -Force
        } -MessageLike '*No .NET SDK*', '*runtime alone*'
        Assert-True (-not (Test-Path $work)) 'no-SDK failure created the work root'
    }
}

Test-Case 'Razor single successful target returns arrays and keeps image and report' {
    Invoke-RazorFixture -Body {
        $png = Join-Path $TempRoot 'razor-single.png'
        $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -Framework 'net8.0' `
            -WorkRoot (Join-Path $TempRoot 'razor-single') -OutputPath $png -Force -Cleanup
        Assert-True $r.Succeeded 'successful single target was reported as incomplete'
        Assert-Equal 1 $r.Results.Count
        Assert-Equal 1 $r.Frameworks.Count
        Assert-Equal 1 $r.Frameworks[0].RuntimePacks.Count
        Assert-True (Test-Path $r.Path) 'image is missing'
        Assert-True ((Get-ImageSize $r.Path).Height -lt 400) 'overview must omit nested runtime asset details'
        Assert-True (Test-Path $r.ReportPath) 'report is missing'
    }
}

Test-Case 'Razor overview preserves names and runtime pack versions without nested asset metadata' {
    $path = Join-Path $ScriptsRoot 'New-RazorMatrix.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $assignments = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true))
    $start = $assignments | Where-Object { $_.Left.Extent.Text -eq '$r.RuntimePacks' }
    $end = $assignments | Where-Object { $_.Left.Extent.Text -eq '$snippets' -and $_.Operator -eq 'PlusEquals' }
    Assert-Equal 1 @($start).Count 'runtime pack extraction block is missing or ambiguous'
    Assert-Equal 1 @($end).Count 'snippet creation block is missing or ambiguous'
    $source = Get-Content -LiteralPath $path -Raw
    $block = [scriptblock]::Create($source.Substring(
        $start.Extent.StartOffset, $end.Extent.EndOffset - $start.Extent.StartOffset))

    $pack = 'runtimepack.Microsoft.NETCore.App.Runtime.win-x64/11.0.0-preview.1'
    $targetName = '.NETCoreApp,Version=v11.0/win-x64'
    $targets = [pscustomobject][ordered]@{
        '.NETCoreApp,Version=v11.0' = [pscustomobject]@{}
        $targetName = [pscustomobject][ordered]@{
            $pack = [pscustomobject]@{ runtime = @{ 'large-asset.dll' = ('x' * 100000) } }
            'Example.Dependency/1.2.3' = [pscustomobject]@{ native = @{ 'native-asset.dll' = @{} } }
        }
    }
    $r = [pscustomobject]@{ RuntimePacks = @() }
    $snippets = @()
    . $block
    Assert-Equal $pack ($r.RuntimePacks -join ',') 'runtime pack version changed'
    Assert-Equal 1 $snippets.Count 'expected one snippet'
    Assert-True ($snippets[0].Length -lt 1000) 'asset payload leaked into the compact snippet'
    Assert-True ($snippets[0] -notmatch 'large-asset|native-asset') 'nested metadata must be omitted'
    $overview = ($snippets[0] | ConvertFrom-Json).targets
    Assert-Equal '.NETCoreApp,Version=v11.0,.NETCoreApp,Version=v11.0/win-x64' `
        (@($overview.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') 'target names/order changed'
    $dependencies = $overview.PSObject.Properties[$targetName].Value
    Assert-Equal "$pack,Example.Dependency/1.2.3" `
        (@($dependencies.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') 'dependency names/order changed'
    Assert-Equal 0 @($dependencies.PSObject.Properties[$pack].Value.PSObject.Properties).Count `
        'dependency values must be empty objects'

    $targets = [pscustomobject]@{ 'empty-target' = [pscustomobject]@{} }
    $snippets = @()
    . $block
    Assert-Equal 0 $r.RuntimePacks.Count 'empty targets must report no runtime packs'
    Assert-Equal 1 $snippets.Count 'empty targets must still render an overview'
}

Test-Case 'Razor continues after new and publish failures and retains detailed output after cleanup' {
    Invoke-RazorFixture -Mode 'mixed' -Body {
        $work = Join-Path $TempRoot 'razor mixed work'
        $png = Join-Path $TempRoot 'razor mixed output\matrix.png'
        $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work -OutputPath $png -Force -Cleanup
        Assert-True (-not $r.Succeeded) 'partial failure must not be reported as complete'
        Assert-Equal 'Failed,Failed,Succeeded,Succeeded' ($r.Results.Status -join ',')
        Assert-Equal 'New,Publish,Complete,Complete' ($r.Results.Stage -join ',')
        Assert-Equal 'net9.0,net8.0' ($r.Frameworks.Framework -join ',') 'lower targets were not attempted'
        Assert-Equal 1 $r.Results[0].Commands.Count 'publish must not run after failed creation'
        Assert-Equal 17 $r.Results[0].Commands[0].ExitCode
        Assert-True ($r.Results[0].Commands[0].StdOut -like '*fixture stdout*') 'stdout lost'
        Assert-True ($r.Results[0].Commands[0].StdErr -like '*unsupported target/template*') 'stderr lost'
        Assert-Equal 'dotnet new razor -f net11.0 -n razor --force --output .' $r.Results[0].Commands[0].Command
        Assert-True ($r.Results[1].Commands[1].Command -like 'dotnet publish -r win-x64 --self-contained*') 'wrong publish command'
        Assert-True (Test-Path $png) 'successful targets did not produce an image'
        Assert-True (-not (Test-Path $work)) 'cleanup did not remove scratch projects'
        $saved = Get-Content -LiteralPath $r.ReportPath -Raw | ConvertFrom-Json
        Assert-Equal 4 $saved.Results.Count 'report must include failed and successful targets'
        Assert-Equal $r.Results[0].Commands[0].StdErr $saved.Results[0].Commands[0].StdErr
    }
}

Test-Case 'Razor reports malformed missing or incomplete deps and continues' {
    Invoke-RazorFixture -Mode 'deps-errors' -Body {
        $png = Join-Path $TempRoot 'razor-deps.png'
        $r = & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot (Join-Path $TempRoot 'razor-deps') `
            -OutputPath $png -Force -Cleanup
        Assert-Equal 'Failed,Failed,Failed,Succeeded' ($r.Results.Status -join ',')
        Assert-Equal 'ReadDeps,ReadDeps,ReadDeps,Complete' ($r.Results.Stage -join ',')
        Assert-True ([bool]$r.Results[0].Error) 'invalid JSON error is missing'
        Assert-True ($r.Results[1].Error -like '*razor.deps.json not found*') 'missing deps error is missing'
        Assert-True ($r.Results[2].Error -like "*no 'targets' section*") 'missing targets error is missing'
        Assert-True (Test-Path $r.ReportPath) 'detailed report is missing'
    }
}

Test-Case 'Razor all-target failure throws only after saving every failure and cleans scratch files' {
    Invoke-RazorFixture -Mode 'all-fail' -Body {
        $work = Join-Path $TempRoot 'razor-all-fail'
        $png = Join-Path $TempRoot 'razor-all-fail.png'
        Assert-Throws {
            & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work -OutputPath $png -Force -Cleanup
        } -MessageLike '*No frameworks produced*', '*detailed report*'
        $saved = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($png, '.report.json')) -Raw | ConvertFrom-Json
        Assert-Equal 4 $saved.Results.Count 'all frameworks must still be attempted'
        Assert-Equal 4 @($saved.Results | Where-Object { $_.Status -eq 'Failed' }).Count
        Assert-Equal $null $saved.Path 'must not report an image on total failure'
        Assert-True (-not (Test-Path $png)) 'no image should be created on total failure'
        Assert-True (-not (Test-Path $work)) 'scratch files survived cleanup'
    }
}

Test-Case 'Razor preserves the existing work-root guard' {
    Invoke-RazorFixture -Body {
        $work = Join-Path $TempRoot 'razor-user-folder'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $work 'user.txt') -Value 'keep'
        Assert-Throws {
            & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work -Force -Cleanup
        } -MessageLike '*was not created by this skill*'
        Assert-Equal 'keep' (Get-Content -LiteralPath (Join-Path $work 'user.txt'))
    }
}

Test-Case 'Razor rejects output inside the work root before creating scratch files' {
    Invoke-RazorFixture -Body {
        $work = Join-Path $TempRoot 'razor-unsafe-output'
        Assert-Throws {
            & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -WorkRoot $work `
                -OutputPath (Join-Path $work 'matrix.png') -Force -Cleanup
        } -MessageLike '*outside WorkRoot*'
        Assert-True (-not (Test-Path $work)) 'rejected output path created the scratch folder'
    }
}

Test-Case 'Razor rejects framework arguments that could escape the scratch directory' {
    $work = Join-Path $TempRoot 'razor-invalid'
    Assert-Throws {
        & (Join-Path $ScriptsRoot 'New-RazorMatrix.ps1') -Framework '..\outside' -WorkRoot $work -Force
    } -MessageLike "*Cannot validate argument on parameter 'Framework'*"
    Assert-True (-not (Test-Path $work)) 'invalid argument created files'
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
