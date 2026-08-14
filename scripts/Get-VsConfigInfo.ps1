<#
.SYNOPSIS
    Collects the local .NET + Visual Studio configuration used by the vs-config-info skill.

.DESCRIPTION
    Gathers, in one pass:
      * a local timestamp, machine and user name
      * every Visual Studio install reported by vswhere (registry fallback)
      * the raw `dotnet --info` output, captured via cmd

    Never fabricates values. When dotnet or vswhere is unavailable the corresponding
    property is $null / empty and the Notes collection explains why.

.PARAMETER AsJson
    Emit JSON instead of a PowerShell object.

.EXAMPLE
    .\Get-VsConfigInfo.ps1

.EXAMPLE
    .\Get-VsConfigInfo.ps1 -AsJson
#>
[CmdletBinding()]
param([switch]$AsJson)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\VsConfigInfo.Common.ps1"

$notes = New-Object System.Collections.Generic.List[string]

# --- .NET -------------------------------------------------------------------
$dotnetInfo    = $null
$sdkVersion    = $null
$installedSdks = @()
$dotnetFound   = [bool](Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)

if ($dotnetFound) {
    $dotnetInfo = (cmd /c "dotnet --info" 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        $notes.Add("dotnet --info exited with code $LASTEXITCODE.")
    }

    # Only the ".NET SDK:" block carries the active SDK version. When no SDK is installed the
    # output begins at "Host:", and a naive ^Version: match reports the HOST version as an SDK
    # version - fabricating a fact the machine cannot support.
    $sdkBlock = [regex]::Match($dotnetInfo, '(?ms)^\.NET SDK:\s*\r?\n(.*?)(?:\r?\n\s*\r?\n|\z)')
    if ($sdkBlock.Success) {
        $match = [regex]::Match($sdkBlock.Groups[1].Value, '(?m)^\s*Version:\s*(\S+)')
        if ($match.Success) { $sdkVersion = $match.Groups[1].Value }
    }

    $listBlock = [regex]::Match($dotnetInfo, '(?ms)^\.NET SDKs installed:\s*\r?\n(.*?)(?:\r?\n\s*\r?\n|\z)')
    if ($listBlock.Success) {
        $installedSdks = @($listBlock.Groups[1].Value -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^No SDKs were found' })
    }

    if ($installedSdks.Count -eq 0) {
        $notes.Add('No .NET SDK is installed - only the runtime/host is present. `dotnet build` and `dotnet new` will not work. Install the SDK from https://dotnet.microsoft.com/download')
    }
}
else {
    $notes.Add('dotnet was not found on PATH. Install the .NET SDK from https://dotnet.microsoft.com/download')
}

# --- Visual Studio ----------------------------------------------------------
$vsInstalls = @()
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

if (Test-Path -LiteralPath $vswhere) {
    $raw = & $vswhere -all -prerelease -format json 2>$null | Out-String
    if ($raw.Trim()) {
        $vsInstalls = @($raw | ConvertFrom-Json | ForEach-Object {
            # Any of these can be absent (Build Tools, damaged or partial installs), and a
            # direct $_.catalog.productDisplayVersion throws PropertyNotFoundStrict.
            [pscustomobject]@{
                DisplayName      = Get-JsonProperty $_ 'displayName'
                ProductVersion   = Get-JsonProperty $_ 'catalog.productDisplayVersion'
                BuildVersion     = Get-JsonProperty $_ 'installationVersion'
                IsPrerelease     = [bool](Get-JsonProperty $_ 'isPrerelease' $false)
                InstallationPath = Get-JsonProperty $_ 'installationPath'
                ProductId        = Get-JsonProperty $_ 'productId'
                ChannelId        = Get-JsonProperty $_ 'channelId'
            }
        })
    }
}
else {
    $notes.Add('vswhere.exe not found; falling back to the registry.')
    $regPath = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup\Instances'
    if (Test-Path -LiteralPath $regPath) {
        $vsInstalls = @(Get-ChildItem -LiteralPath $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            [pscustomobject]@{
                DisplayName      = Get-JsonProperty $p 'DisplayName'
                ProductVersion   = Get-JsonProperty $p 'InstallationVersion'
                BuildVersion     = Get-JsonProperty $p 'InstallationVersion'
                IsPrerelease     = $null
                InstallationPath = Get-JsonProperty $p 'InstallationPath'
                ProductId        = $null
                ChannelId        = $null
            }
        })
    }
    if (-not $vsInstalls) {
        $notes.Add('Visual Studio not detected (vswhere.exe not found and no registry instances).')
    }
}

$result = [pscustomobject]@{
    Timestamp     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
    Machine       = $env:COMPUTERNAME
    User          = $env:USERNAME
    DotnetFound   = $dotnetFound
    DotnetRoot    = (Get-DotnetRootPath)
    SdkVersion    = $sdkVersion
    SdkCount      = $installedSdks.Count
    InstalledSdks = $installedSdks
    DotnetInfo    = $dotnetInfo
    VisualStudio  = $vsInstalls
    Notes         = $notes.ToArray()
}

if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { $result }
