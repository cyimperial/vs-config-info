<#
.SYNOPSIS
    Builds a Razor Pages app on several target frameworks and renders the stacked
    razor.deps.json targets sections as a single PNG.

.DESCRIPTION
    EXPENSIVE AND DESTRUCTIVE - this is the only format in the skill that writes
    outside the session folder and consumes real time and disk. Guard rails:

      * Dry run by default. Nothing is created unless -Force is supplied.
      * Each framework builds in its OWN subfolder, so `dotnet new --force`
        can never overwrite another framework's project (or a user's files).
      * -WorkRoot defaults to a scratch folder under $env:LOCALAPPDATA - never a
        hardcoded user profile path - and refuses to run against a non-empty
        folder it did not create unless -AllowExistingWorkRoot is supplied.
      * Frameworks whose SDK is not installed are skipped, not failed.
      * -Cleanup removes the build output when finished.

    Self-contained win-x64 publishes are roughly 100-200 MB per framework.

.PARAMETER Framework
    Target frameworks, rendered top-to-bottom in the order given.
    Defaults to net10.0, net9.0, net8.0.

.PARAMETER WorkRoot
    Scratch folder for the generated projects.

.PARAMETER OutputPath
    Full path of the PNG. Defaults to razor-matrix.png in a timestamped session folder.

.PARAMETER Force
    Actually run. Without this the script only reports its plan.

.PARAMETER Cleanup
    Delete the work root after rendering.

.EXAMPLE
    .\New-RazorMatrix.ps1                      # dry run - shows the plan only

.EXAMPLE
    .\New-RazorMatrix.ps1 -Force -Cleanup
#>
[CmdletBinding()]
param(
    [string[]]$Framework = @('net10.0', 'net9.0', 'net8.0'),
    [string]$WorkRoot,
    [string]$OutputPath,
    [string]$OutputRoot,
    [switch]$Force,
    [switch]$Cleanup,
    [switch]$AllowExistingWorkRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\VsConfigInfo.Common.ps1"

if (-not (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'dotnet was not found on PATH. Install the .NET SDK from https://dotnet.microsoft.com/download'
}

if (-not $WorkRoot) {
    $WorkRoot = Join-Path $env:LOCALAPPDATA 'vs-config-info\razor-matrix'
}

# --- Which frameworks can actually build? -----------------------------------
$installedMajors = @(dotnet --list-sdks |
    ForEach-Object { [regex]::Match($_, '^(\d+)\.').Groups[1].Value } |
    Where-Object { $_ } |
    Sort-Object -Unique)

$plan = foreach ($tfm in $Framework) {
    $major = [regex]::Match($tfm, '^net(\d+)\.').Groups[1].Value
    [pscustomobject]@{
        Framework = $tfm
        Major     = $major
        Supported = ($installedMajors -contains $major)
        Directory = Join-Path $WorkRoot $tfm
    }
}

Write-Host "Razor matrix plan (work root: $WorkRoot)"
foreach ($p in $plan) {
    $state = if ($p.Supported) { 'build' } else { 'SKIP - no matching SDK installed' }
    Write-Host ("  {0,-9} {1}" -f $p.Framework, $state)
}

$buildable = @($plan | Where-Object Supported)

if (-not $Force) {
    Write-Host ''
    if ($buildable.Count -eq 0) {
        Write-Host 'Nothing to build - none of the requested frameworks have a matching SDK installed.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'DRY RUN - nothing was created. Re-run with -Force to build.' -ForegroundColor Yellow
        Write-Host ("Estimated cost: {0} self-contained win-x64 publishes (~100-200 MB each)." -f $buildable.Count)
    }
    return [pscustomobject]@{ DryRun = $true; Plan = $plan; WorkRoot = $WorkRoot; Path = $null }
}

if (-not $buildable) {
    throw "None of the requested frameworks ($($Framework -join ', ')) have a matching SDK installed."
}

# --- Work root safety -------------------------------------------------------
if ((Test-Path -LiteralPath $WorkRoot) -and -not $AllowExistingWorkRoot) {
    $existing = @(Get-ChildItem -LiteralPath $WorkRoot -Force -ErrorAction SilentlyContinue)
    $marker   = Join-Path $WorkRoot '.vs-config-info'
    if ($existing.Count -gt 0 -and -not (Test-Path -LiteralPath $marker)) {
        throw "Work root '$WorkRoot' already exists and was not created by this skill. " +
              'Pass -AllowExistingWorkRoot to use it anyway, or choose a different -WorkRoot.'
    }
}

New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $WorkRoot '.vs-config-info') -Value 'scratch folder created by the vs-config-info skill'

# --- Build ------------------------------------------------------------------
$results = @()
foreach ($p in $buildable) {
    Write-Host "`n=== $($p.Framework) ===" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $p.Directory -Force | Out-Null

    # Isolated per-TFM directory: --force can only ever affect this framework.
    & dotnet new razor -f $p.Framework -o $p.Directory -n razor --force | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "dotnet new failed for $($p.Framework)"; continue }

    & dotnet publish $p.Directory -r win-x64 --self-contained | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "dotnet publish failed for $($p.Framework)"; continue }

    $deps = Get-ChildItem -LiteralPath $p.Directory -Recurse -Filter 'razor.deps.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\publish\\' } |
        Select-Object -First 1

    if (-not $deps) { Write-Warning "razor.deps.json not found for $($p.Framework)"; continue }

    $json    = Get-Content -LiteralPath $deps.FullName -Raw | ConvertFrom-Json
    $targets = Get-JsonProperty $json 'targets'
    if (-not $targets) {
        Write-Warning "razor.deps.json for $($p.Framework) has no 'targets' section."
        continue
    }
    $snippet = [pscustomobject]@{ targets = $targets } | ConvertTo-Json -Depth 8

    $runtimePacks = @($targets.PSObject.Properties |
        ForEach-Object { $_.Value.PSObject.Properties.Name } |
        Where-Object { $_ -like 'runtimepack.*' } |
        Sort-Object -Unique)

    $results += [pscustomobject]@{
        Framework    = $p.Framework
        DepsPath     = $deps.FullName
        Snippet      = $snippet
        RuntimePacks = $runtimePacks
    }
}

if (-not $results) { throw 'No frameworks produced a razor.deps.json.' }

# --- Render -----------------------------------------------------------------
if (-not $OutputPath) {
    $folder = New-VsConfigTimestampFolder -OutputRoot $OutputRoot
    $OutputPath = Join-Path $folder 'razor-matrix.png'
}

$image = & "$PSScriptRoot\New-JsonSnippetImage.ps1" -Snippet ($results.Snippet) -OutputPath $OutputPath

if ($Cleanup) {
    Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned up $WorkRoot"
}

foreach ($r in $results) {
    Write-Host ("{0,-9} runtimepacks: {1}" -f $r.Framework, ($r.RuntimePacks -join ', '))
}

[pscustomobject]@{
    DryRun    = $false
    Path      = $image.Path
    WorkRoot  = $WorkRoot
    Frameworks = @($results | Select-Object Framework, RuntimePacks)
}
