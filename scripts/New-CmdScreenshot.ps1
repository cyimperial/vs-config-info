<#
.SYNOPSIS
    Renders `dotnet --info` (or any cmd command) as a Command Prompt-styled PNG.

.DESCRIPTION
    Draws the captured stdout onto a bitmap using Consolas 12pt on the real cmd
    palette (#0C0C0C background, #CCCCCC foreground) and prepends a prompt line so
    the image reads like a genuine terminal session.

    Filename is derived in this priority order when -OutputPath is not supplied:
      1. vs-<highest vswhere productDisplayVersion>.png
      2. dotnet-sdk-<sdk version>.png
      3. vs-config-info.png

.PARAMETER Command
    The cmd command to run and capture. Defaults to 'dotnet --info'.

.PARAMETER OutputPath
    Full path of the PNG to write. Overrides the derived filename.

.PARAMETER OutputRoot
    Folder to write into when -OutputPath is not supplied. Defaults to the current
    Copilot session files folder (see Get-VsConfigOutputRoot).

.PARAMETER FileName
    Fixed filename (e.g. 'dotnet-info.png' for the All-in-one bundle).

.EXAMPLE
    .\New-CmdScreenshot.ps1

.EXAMPLE
    .\New-CmdScreenshot.ps1 -OutputRoot 'C:\temp\0814-2230' -FileName 'dotnet-info.png'
#>
[CmdletBinding()]
param(
    [string]$Command = 'dotnet --info',
    [string]$OutputPath,
    [string]$OutputRoot,
    [string]$FileName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\VsConfigInfo.Common.ps1"

# --- Capture ----------------------------------------------------------------
$output = (cmd /c $Command 2>&1 | Out-String)
if (-not $output.Trim()) {
    throw "Command produced no output: $Command"
}

$promptLine = "$($env:USERPROFILE)>$Command"
$lines = @($promptLine) + @($output -split "`r?`n")

# Trim trailing blank lines so the image has no dead space.
while ($lines.Count -gt 1 -and -not $lines[-1].Trim()) {
    $lines = $lines[0..($lines.Count - 2)]
}

# --- Resolve output path ----------------------------------------------------
if (-not $OutputPath) {
    if (-not $FileName) {
        $FileName = 'vs-config-info.png'
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        $vsVersion = $null

        if (Test-Path -LiteralPath $vswhere) {
            $raw = & $vswhere -all -prerelease -format json 2>$null | Out-String
            if ($raw.Trim()) {
                # productDisplayVersion is free text and may be e.g. "Insiders [12023.133]",
                # and some installs (Build Tools) omit `catalog` entirely - both are handled
                # by Get-JsonProperty + ConvertTo-SortableVersion rather than a [version] cast.
                $vsVersion = ($raw | ConvertFrom-Json |
                    ForEach-Object { Get-JsonProperty $_ 'catalog.productDisplayVersion' } |
                    Where-Object { $_ } |
                    Sort-Object -Descending { ConvertTo-SortableVersion $_ } |
                    Select-Object -First 1)
            }
        }

        if ($vsVersion) {
            $FileName = "vs-$(ConvertTo-SafeFileNamePart $vsVersion).png"
        }
        else {
            $m = [regex]::Match($output, '(?m)^\s*Version:\s*(\S+)')
            if ($m.Success) {
                $FileName = "dotnet-sdk-$(ConvertTo-SafeFileNamePart $m.Groups[1].Value).png"
            }
        }
    }

    $root = Get-VsConfigOutputRoot -OutputRoot $OutputRoot
    $OutputPath = Join-Path $root $FileName
}

# --- Draw -------------------------------------------------------------------
$font = [System.Drawing.Font]::new('Consolas', 12)
$fmt  = New-VsConfigStringFormat

$measure = New-VsConfigBitmap -Width 1 -Height 1
try {
    $maxWidth = 0
    foreach ($line in $lines) {
        $w = $measure.Graphics.MeasureString($line, $font, [int]::MaxValue, $fmt).Width
        if ($w -gt $maxWidth) { $maxWidth = $w }
    }
}
finally {
    $measure.Graphics.Dispose()
    $measure.Bitmap.Dispose()
}

$lineHeight = [int]$font.Height
$padding    = 20
$width      = [int][Math]::Ceiling($maxWidth) + ($padding * 2)
$height     = ($lines.Count * $lineHeight) + ($padding * 2)

$bg = [System.Drawing.ColorTranslator]::FromHtml('#0C0C0C')
$fg = [System.Drawing.ColorTranslator]::FromHtml('#CCCCCC')

$canvas = New-VsConfigBitmap -Width $width -Height $height -Background $bg
$brush  = [System.Drawing.SolidBrush]::new($fg)

$y = $padding
foreach ($line in $lines) {
    $canvas.Graphics.DrawString($line, $font, $brush, [System.Drawing.PointF]::new($padding, $y), $fmt)
    $y += $lineHeight
}

$brush.Dispose()
$font.Dispose()
$fmt.Dispose()

$saved = Save-VsConfigBitmap -Bitmap $canvas.Bitmap -Graphics $canvas.Graphics -Path $OutputPath

[pscustomobject]@{
    Path      = $saved
    FileName  = Split-Path -Leaf $saved
    LineCount = $lines.Count
    Width     = $width
    Height    = $height
}
