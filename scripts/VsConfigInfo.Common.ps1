# VsConfigInfo.Common.ps1
# Shared helpers for the vs-config-info skill scripts.
# Dot-source this file:  . "$PSScriptRoot\VsConfigInfo.Common.ps1"

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

function Get-VsConfigOutputRoot {
    <#
    .SYNOPSIS
        Resolves the folder where generated artifacts are written.
    .DESCRIPTION
        Never hardcodes a user name. Resolution order:
          1. -OutputRoot argument
          2. $env:COPILOT_SESSION_FILES
          3. Newest folder under $env:USERPROFILE\.copilot\session-state, plus \files
          4. $env:TEMP\vs-config-info
    #>
    [CmdletBinding()]
    param([string]$OutputRoot)

    if ($OutputRoot) {
        return (New-Item -ItemType Directory -Path $OutputRoot -Force).FullName
    }

    if ($env:COPILOT_SESSION_FILES -and (Test-Path -LiteralPath $env:COPILOT_SESSION_FILES)) {
        return (Resolve-Path -LiteralPath $env:COPILOT_SESSION_FILES).Path
    }

    $stateRoot = Join-Path $env:USERPROFILE '.copilot\session-state'
    if (Test-Path -LiteralPath $stateRoot) {
        $newest = Get-ChildItem -LiteralPath $stateRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($newest) {
            return (New-Item -ItemType Directory -Path (Join-Path $newest.FullName 'files') -Force).FullName
        }
    }

    return (New-Item -ItemType Directory -Path (Join-Path $env:TEMP 'vs-config-info') -Force).FullName
}

function New-VsConfigTimestampFolder {
    <#
    .SYNOPSIS
        Creates (and returns) an MMDD-HHMM folder under the resolved output root.
    #>
    [CmdletBinding()]
    param([string]$OutputRoot)

    $root  = Get-VsConfigOutputRoot -OutputRoot $OutputRoot
    $stamp = Get-Date -Format 'MMdd-HHmm'
    return (New-Item -ItemType Directory -Path (Join-Path $root $stamp) -Force).FullName
}

function Get-DotnetRootPath {
    <#
    .SYNOPSIS
        Locates the active dotnet install root without assuming C:\Program Files\dotnet.
    .DESCRIPTION
        Honours $env:DOTNET_ROOT, then the resolved location of dotnet on PATH,
        then falls back to the default Program Files location.
    #>
    [CmdletBinding()]
    param()

    if ($env:DOTNET_ROOT -and (Test-Path -LiteralPath $env:DOTNET_ROOT)) {
        return (Resolve-Path -LiteralPath $env:DOTNET_ROOT).Path
    }

    $cmd = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) {
        return (Split-Path -Parent $cmd.Source)
    }

    $fallback = Join-Path $env:ProgramFiles 'dotnet'
    if (Test-Path -LiteralPath $fallback) { return $fallback }

    return $null
}

function Get-DotnetInstallRoots {
    <#
    .SYNOPSIS
        Returns the three folder roots the "Folder icons" format renders.
    #>
    [CmdletBinding()]
    param()

    $dotnetRoot = Get-DotnetRootPath
    if (-not $dotnetRoot) { return @() }

    return @(
        [pscustomobject]@{ Name = 'sdk';         Path = Join-Path $dotnetRoot 'sdk' }
        [pscustomobject]@{ Name = 'netcore-app'; Path = Join-Path $dotnetRoot 'shared\Microsoft.NETCore.App' }
        [pscustomobject]@{ Name = 'templates';   Path = Join-Path $dotnetRoot 'templates' }
    )
}

function Get-JsonProperty {
    <#
    .SYNOPSIS
        Reads a dotted property path without throwing under Set-StrictMode -Version Latest.
    .DESCRIPTION
        `$obj.missing` raises PropertyNotFoundStrict under StrictMode, which crashes the whole
        skill on perfectly normal input - vswhere entries for Build Tools installs, for example,
        can omit `catalog` entirely. Indexing PSObject.Properties returns $null instead.
    .EXAMPLE
        Get-JsonProperty $install 'catalog.productDisplayVersion'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]$InputObject,
        [Parameter(Mandatory, Position = 1)][string]$Path,
        [Parameter(Position = 2)]$Default = $null
    )

    $current = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $Default }
        $property = $current.PSObject.Properties[$segment]
        if (-not $property) { return $Default }
        $current = $property.Value
    }

    if ($null -eq $current) { return $Default }
    return $current
}

function ConvertTo-SortableVersion {
    <#
    .SYNOPSIS
        Extracts the first dotted-numeric run from free-form text so it can be sorted.
    .DESCRIPTION
        Version text is not always a version: Visual Studio reports things like
        "Insiders [12023.133]", and casting that to [version] throws. Folder names such as
        "9.0.17" must also sort before "10.0.9", which a string sort gets wrong.
    #>
    [CmdletBinding()]
    param([string]$Text)

    if ($Text) {
        $match = [regex]::Match($Text, '\d+(?:\.\d+)+')
        if ($match.Success) {
            try { return [version]$match.Value } catch { }
        }
    }
    return [version]'0.0'
}

function ConvertTo-SafeFileNamePart {
    <#
    .SYNOPSIS
        Makes free-form version text safe to embed in a filename.
    .EXAMPLE
        ConvertTo-SafeFileNamePart 'Insiders [12023.133]'   # -> Insiders-12023.133
    #>
    [CmdletBinding()]
    param([string]$Text)

    if (-not $Text) { return 'unknown' }

    $invalid = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
    $safe = $Text -replace "[$invalid]", '-'
    $safe = $safe -replace '[\[\]\s]+', '-'
    $safe = $safe -replace '-{2,}', '-'
    $safe = $safe.Trim('-')

    if (-not $safe) { return 'unknown' }
    return $safe
}

function Format-JsonIndent {
    <#
    .SYNOPSIS
        Re-indents JSON with a canonical 2-space style, collapsing empty {} and [].
    .DESCRIPTION
        Windows PowerShell 5.1's ConvertTo-Json emits ragged indentation that pushes closing
        braces far to the right, which inflates rendered image width. This walks the text
        tracking string/escape state and rebuilds the layout.
    #>
    [CmdletBinding()]
    param([string]$Json, [int]$IndentSize = 2)

    $sb       = [System.Text.StringBuilder]::new()
    $depth    = 0
    $inString = $false
    $escaped  = $false

    $pad = { param($n) ' ' * ($n * $IndentSize) }

    for ($i = 0; $i -lt $Json.Length; $i++) {
        $ch = $Json[$i]

        if ($inString) {
            [void]$sb.Append($ch)
            if ($escaped)        { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }

        switch ($ch) {
            '"' { $inString = $true; [void]$sb.Append($ch) }
            '{' {
                $next = ($Json.Substring($i + 1) -replace '^\s+', '')
                if ($next.StartsWith('}')) {
                    [void]$sb.Append('{}')
                    $i = $Json.IndexOf('}', $i + 1)
                }
                else {
                    $depth++
                    [void]$sb.Append("{`n").Append((& $pad $depth))
                }
            }
            '[' {
                $next = ($Json.Substring($i + 1) -replace '^\s+', '')
                if ($next.StartsWith(']')) {
                    [void]$sb.Append('[]')
                    $i = $Json.IndexOf(']', $i + 1)
                }
                else {
                    $depth++
                    [void]$sb.Append("[`n").Append((& $pad $depth))
                }
            }
            '}' { $depth--; [void]$sb.Append("`n").Append((& $pad $depth)).Append('}') }
            ']' { $depth--; [void]$sb.Append("`n").Append((& $pad $depth)).Append(']') }
            ',' { [void]$sb.Append(",`n").Append((& $pad $depth)) }
            ':' { [void]$sb.Append(': ') }
            default {
                if ($ch -notmatch '\s') { [void]$sb.Append($ch) }
            }
        }
    }

    return $sb.ToString()
}

function New-VsConfigBitmap {
    <#
    .SYNOPSIS
        Creates a bitmap + graphics pair with high-quality text rendering enabled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [System.Drawing.Color]$Background = [System.Drawing.Color]::Black
    )

    $bmp = [System.Drawing.Bitmap]::new([Math]::Max($Width, 1), [Math]::Max($Height, 1))
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($Background)

    return [pscustomobject]@{ Bitmap = $bmp; Graphics = $g }
}

function New-VsConfigStringFormat {
    <#
    .SYNOPSIS
        StringFormat that never wraps or ellipsizes a label (e.g. keeps "10.0.300" intact).
    #>
    [CmdletBinding()]
    param([System.Drawing.StringAlignment]$Alignment = [System.Drawing.StringAlignment]::Near)

    $fmt = [System.Drawing.StringFormat]::new()
    $fmt.Alignment   = $Alignment
    $fmt.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $fmt.Trimming    = [System.Drawing.StringTrimming]::None
    return $fmt
}

function Save-VsConfigBitmap {
    <#
    .SYNOPSIS
        Saves a bitmap as PNG and disposes both bitmap and graphics (no leaked handles).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    try {
        $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }

    return (Resolve-Path -LiteralPath $Path).Path
}
