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
      * Every framework is attempted with the available SDK/templates, without
        requiring a same-major SDK or a locally installed target runtime.
      * Failures retain command output in a JSON report; other frameworks continue.
      * -Cleanup removes the build output, but keeps the report and image.

    Self-contained win-x64 publishes are roughly 100-200 MB per framework.

.PARAMETER Framework
    Target frameworks, rendered top-to-bottom in the order given.
    Defaults to net11.0, net10.0, net9.0, net8.0.

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
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^net[1-9]\d*\.\d+$')]
    [string[]]$Framework = @('net11.0', 'net10.0', 'net9.0', 'net8.0'),
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

function Invoke-RazorDotnet {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $Executable
    # Arguments are fixed switches and validated TFMs; paths use WorkingDirectory.
    $process.StartInfo.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process.StartInfo.WorkingDirectory = $Directory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            Command = 'dotnet ' + ($Arguments -join ' ')
            Directory = $Directory
            ExitCode = $process.ExitCode
            StdOut = $stdout.GetAwaiter().GetResult()
            StdErr = $stderr.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

if (-not $WorkRoot) {
    $WorkRoot = Join-Path $env:LOCALAPPDATA 'vs-config-info\razor-matrix'
}
$WorkRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkRoot)

# --- Plan attempts, not guaranteed template/target support -------------------
$dotnet = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$sdkProbe = $null
$installedSdks = @()
$reason = 'dotnet was not found on PATH. Install the .NET SDK, not just a runtime.'
if ($dotnet) {
    $sdkProbe = Invoke-RazorDotnet -Executable $dotnet.Source -Arguments '--list-sdks' -Directory (Get-Location).Path
    if ($sdkProbe.ExitCode -ne 0) {
        $reason = "dotnet --list-sdks failed (exit $($sdkProbe.ExitCode)).`n$($sdkProbe.StdOut)`n$($sdkProbe.StdErr)"
    }
    else {
        $installedSdks = @($sdkProbe.StdOut -split '\r?\n' | Where-Object { $_.Trim() })
        $reason = 'No .NET SDK is installed. A runtime alone cannot run dotnet new or dotnet publish.'
    }
}
$canAttempt = $installedSdks.Count -gt 0

$plan = @(foreach ($tfm in ($Framework | Select-Object -Unique)) {
    [pscustomobject]@{
        Framework = $tfm
        Supported = $canAttempt
        Reason    = if ($canAttempt) { 'Attempt with available SDK/templates; support is determined by the commands.' } else { $reason }
        Directory = Join-Path $WorkRoot $tfm
    }
})

Write-Host "Razor matrix plan (work root: $WorkRoot)"
foreach ($p in $plan) {
    $state = if ($p.Supported) { 'attempt new + self-contained publish (win-x64)' } else { "SKIP - $($p.Reason)" }
    Write-Host ("  {0,-9} {1}" -f $p.Framework, $state)
}

$buildable = @($plan | Where-Object Supported)

if (-not $Force) {
    Write-Host ''
    if ($buildable.Count -eq 0) {
        Write-Host $reason -ForegroundColor Yellow
    }
    else {
        Write-Host 'DRY RUN - nothing was created. Re-run with -Force to build.' -ForegroundColor Yellow
        Write-Host ("Estimated cost: {0} self-contained win-x64 publishes (~100-200 MB each)." -f $buildable.Count)
    }
    return [pscustomobject]@{
        DryRun = $true; Plan = $plan; WorkRoot = $WorkRoot; Path = $null
        InstalledSdks = $installedSdks; SdkProbe = $sdkProbe
    }
}

if (-not $buildable) {
    throw "Cannot attempt Razor matrix: $reason"
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

if (-not $OutputPath) {
    $folder = New-VsConfigTimestampFolder -OutputRoot $OutputRoot
    $OutputPath = Join-Path $folder 'razor-matrix.png'
}

$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$reportPath = [System.IO.Path]::ChangeExtension($OutputPath, '.report.json')
if ($reportPath.StartsWith($WorkRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be outside WorkRoot so cleanup cannot delete the image or report.'
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $WorkRoot '.vs-config-info') -Value 'scratch folder created by the vs-config-info skill'

# A unique publish directory prevents a previous run's deps file from being reused.
$publishDirectory = 'bin\publish-' + [guid]::NewGuid().ToString('N')
$results = @()
$snippets = @()
try {
    foreach ($p in $buildable) {
        Write-Host "`n=== $($p.Framework) ===" -ForegroundColor Cyan
        $r = [pscustomobject]@{
            Framework = $p.Framework; Status = 'Failed'; Stage = 'Prepare'
            Directory = $p.Directory; Commands = @(); Error = $null
            DepsPath = $null; RuntimePacks = @()
        }
        try {
            New-Item -ItemType Directory -Path $p.Directory -Force | Out-Null
            $r.Stage = 'New'
            $command = Invoke-RazorDotnet -Executable $dotnet.Source -Directory $p.Directory `
                -Arguments @('new', 'razor', '-f', $p.Framework, '-n', 'razor', '--force', '--output', '.')
            $r.Commands += $command
            if ($command.ExitCode -ne 0) { throw "dotnet new failed (exit $($command.ExitCode))." }

            $r.Stage = 'Publish'
            $command = Invoke-RazorDotnet -Executable $dotnet.Source -Directory $p.Directory `
                -Arguments @('publish', '-r', 'win-x64', '--self-contained', '-o', $publishDirectory)
            $r.Commands += $command
            if ($command.ExitCode -ne 0) { throw "dotnet publish failed (exit $($command.ExitCode))." }

            $r.Stage = 'ReadDeps'
            $r.DepsPath = Join-Path (Join-Path $p.Directory $publishDirectory) 'razor.deps.json'
            if (-not (Test-Path -LiteralPath $r.DepsPath)) { throw "razor.deps.json not found at $($r.DepsPath)" }
            $json = Get-Content -LiteralPath $r.DepsPath -Raw | ConvertFrom-Json
            $targets = Get-JsonProperty $json 'targets'
            if (-not $targets) { throw "razor.deps.json has no 'targets' section." }
            $r.RuntimePacks = @($targets.PSObject.Properties |
                ForEach-Object {
                    foreach ($property in $_.Value.PSObject.Properties) {
                        $property.Name
                    }
                } |
                Where-Object { $_ -like 'runtimepack.*' } |
                Sort-Object -Unique)

            $targetOverview = [ordered]@{}
            foreach ($target in $targets.PSObject.Properties) {
                $dependencies = [ordered]@{}
                foreach ($dependency in $target.Value.PSObject.Properties) {
                    $dependencies[$dependency.Name] = [pscustomobject]@{}
                }
                $targetOverview[$target.Name] = $dependencies
            }
            $snippets += [pscustomobject]@{
                targets = $targetOverview
            } | ConvertTo-Json -Depth 8
            $r.Status = 'Succeeded'
            $r.Stage = 'Complete'
        }
        catch {
            $r.Error = $_.Exception.Message
            Write-Warning ("{0}: {1} failed. {2}" -f $r.Framework, $r.Stage, $r.Error)
            foreach ($c in $r.Commands) {
                if ($c.ExitCode -ne 0) {
                    Write-Host ("Command: {0}`nDirectory: {1}`nExit code: {2}`nSTDOUT:`n{3}`nSTDERR:`n{4}" -f
                        $c.Command, $c.Directory, $c.ExitCode, $c.StdOut, $c.StdErr)
                }
            }
        }
        $results += $r
    }

    $successful = @($results | Where-Object { $_.Status -eq 'Succeeded' })
    $report = [pscustomobject]@{
        DryRun = $false; Succeeded = ($successful.Count -eq $results.Count)
        Path = $null; ReportPath = $reportPath; WorkRoot = $WorkRoot
        InstalledSdks = $installedSdks; SdkProbe = $sdkProbe; Results = $results
        Frameworks = @($successful | Select-Object Framework, RuntimePacks)
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Detailed Razor matrix report: $reportPath"
    if (-not $successful) { throw "No frameworks produced a razor.deps.json. See detailed report: $reportPath" }

    $image = & "$PSScriptRoot\New-JsonSnippetImage.ps1" -Snippet $snippets -OutputPath $OutputPath
    $report.Path = $image.Path
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    foreach ($r in $results) {
        Write-Host ("{0,-9} {1}; stage: {2}; runtimepacks: {3}" -f
            $r.Framework, $r.Status, $r.Stage, ($r.RuntimePacks -join ', '))
    }
    if (-not $report.Succeeded) { Write-Warning "Razor matrix is incomplete. See detailed report: $reportPath" }
    $report
}
finally {
    if ($Cleanup) {
        Remove-Item -LiteralPath $WorkRoot -Recurse -Force
        Write-Host "Cleaned up $WorkRoot"
    }
}
