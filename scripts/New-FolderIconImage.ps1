<#
.SYNOPSIS
    Renders the subfolders of a dotnet install root as Explorer-style folder-icon rows.

.DESCRIPTION
    Replaces the broken inline Draw-FolderIcon snippet that previously lived in SKILL.md.

    Layout is one HORIZONTAL ROW per subfolder: a yellow Windows-style folder icon on
    the left, the exact folder name to its right. Labels are measured with the same
    font used to draw them and rendered with NoWrap + Trimming::None, so a version such
    as "10.0.300" can never be clipped to "1" or ellipsized to "10.0...".

    After saving, the script asserts that the row count equals the directory count and
    returns the labels it drew so the caller can verify them.

.PARAMETER Root
    The folder whose subfolders are rendered, e.g. "$env:ProgramFiles\dotnet\sdk".

.PARAMETER OutputPath
    Full path of the PNG to write.

.PARAMETER IconSize
    Height of each folder icon in pixels. Default 48.

.EXAMPLE
    .\New-FolderIconImage.ps1 -Root "$env:ProgramFiles\dotnet\sdk" -OutputPath .\sdk.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$IconSize = 48
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\VsConfigInfo.Common.ps1"

function Add-FolderIcon {
    <#
    .SYNOPSIS
        Draws a single Windows-style folder glyph. Draws the icon ONLY - the caller
        positions the label to the right of it.
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Size
    )

    $backColor  = [System.Drawing.ColorTranslator]::FromHtml('#E8B233')
    $frontColor = [System.Drawing.ColorTranslator]::FromHtml('#FFC83D')

    $back  = [System.Drawing.SolidBrush]::new($backColor)
    $front = [System.Drawing.SolidBrush]::new($frontColor)

    try {
        # Back panel + tab
        $tab = [System.Drawing.Rectangle]::new(
            [int]($X + $Size * 0.04),
            [int]($Y + $Size * 0.16),
            [int]($Size * 0.44),
            [int]($Size * 0.16))
        $Graphics.FillRectangle($back, $tab)

        $backPanel = [System.Drawing.Rectangle]::new(
            [int]($X + $Size * 0.04),
            [int]($Y + $Size * 0.26),
            [int]($Size * 0.92),
            [int]($Size * 0.50))
        $Graphics.FillRectangle($back, $backPanel)

        # Front panel
        $body = [System.Drawing.Rectangle]::new(
            [int]($X + $Size * 0.04),
            [int]($Y + $Size * 0.32),
            [int]($Size * 0.92),
            [int]($Size * 0.48))
        $Graphics.FillRectangle($front, $body)
    }
    finally {
        $back.Dispose()
        $front.Dispose()
    }
}

# --- Enumerate --------------------------------------------------------------
$missing = -not (Test-Path -LiteralPath $Root)
$labels  = @()

if (-not $missing) {
    $labels = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name |
        Sort-Object { ConvertTo-SortableVersion $_ }, { $_ })
}

$font   = [System.Drawing.Font]::new('Segoe UI', 11)
$fmt    = New-VsConfigStringFormat
$bg     = [System.Drawing.ColorTranslator]::FromHtml('#202020')
$fgHtml = '#F0F0F0'

if ($missing -or $labels.Count -eq 0) {
    $message = if ($missing) { "Path not found: $Root" } else { "No subfolders found in: $Root" }

    $probe = New-VsConfigBitmap -Width 1 -Height 1
    try {
        $size = $probe.Graphics.MeasureString($message, $font, [int]::MaxValue, $fmt)
    }
    finally {
        $probe.Graphics.Dispose()
        $probe.Bitmap.Dispose()
    }

    $canvas = New-VsConfigBitmap -Width ([int][Math]::Ceiling($size.Width) + 40) `
                                 -Height ([int][Math]::Ceiling($size.Height) + 40) `
                                 -Background $bg
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($fgHtml))
    $canvas.Graphics.DrawString($message, $font, $brush, [System.Drawing.PointF]::new(20, 20), $fmt)
    $brush.Dispose()

    $saved = Save-VsConfigBitmap -Bitmap $canvas.Bitmap -Graphics $canvas.Graphics -Path $OutputPath
    $font.Dispose(); $fmt.Dispose()

    Write-Host ("[{0}] rows=0 verified=True note={1}" -f (Split-Path -Leaf $saved), $message)

    return [pscustomobject]@{
        Path      = $saved
        Root      = $Root
        Labels    = @()
        RowCount  = 0
        Verified  = $true
        Message   = $message
    }
}

# --- Measure ----------------------------------------------------------------
$gap         = 14   # space between icon and label
$marginX     = 18
$marginY     = 14
$rowSpacing  = 10
$rowHeight   = [Math]::Max($IconSize, [int]$font.Height)

$probe = New-VsConfigBitmap -Width 1 -Height 1
try {
    $maxLabelWidth = 0
    foreach ($label in $labels) {
        $w = $probe.Graphics.MeasureString($label, $font, [int]::MaxValue, $fmt).Width
        if ($w -gt $maxLabelWidth) { $maxLabelWidth = $w }
    }
}
finally {
    $probe.Graphics.Dispose()
    $probe.Bitmap.Dispose()
}

# Width = margin + icon + gap + measured label + right margin (+2px safety)
$width  = $marginX + $IconSize + $gap + [int][Math]::Ceiling($maxLabelWidth) + 2 + $marginX
$height = ($marginY * 2) + ($labels.Count * $rowHeight) + (($labels.Count - 1) * $rowSpacing)

# --- Draw -------------------------------------------------------------------
$canvas = New-VsConfigBitmap -Width $width -Height $height -Background $bg
$brush  = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($fgHtml))

$y = $marginY
foreach ($label in $labels) {
    Add-FolderIcon -Graphics $canvas.Graphics -X $marginX -Y $y -Size $IconSize

    $labelX = $marginX + $IconSize + $gap
    $labelY = $y + (($rowHeight - $font.Height) / 2)
    # PointF (not a fixed-width RectangleF) so horizontal labels are never clipped.
    $canvas.Graphics.DrawString($label, $font, $brush,
        [System.Drawing.PointF]::new([single]$labelX, [single]$labelY), $fmt)

    $y += $rowHeight + $rowSpacing
}

$brush.Dispose()
$font.Dispose()
$fmt.Dispose()

$saved = Save-VsConfigBitmap -Bitmap $canvas.Bitmap -Graphics $canvas.Graphics -Path $OutputPath

# --- Verify -----------------------------------------------------------------
$actual   = @(Get-ChildItem -LiteralPath $Root -Directory | Select-Object -ExpandProperty Name)
$verified = ($labels.Count -eq $actual.Count) -and
            (-not (Compare-Object -ReferenceObject $labels -DifferenceObject $actual))

if (-not $verified) {
    Write-Warning "Row/label verification failed for $Root."
}

# Summary on the host stream so callers using `powershell -File` (which flattens
# object output to text) can still confirm the row/label assertion.
Write-Host ("[{0}] rows={1} verified={2} labels={3}" -f `
    (Split-Path -Leaf $saved), $labels.Count, $verified, ($labels -join ', '))

[pscustomobject]@{
    Path     = $saved
    Root     = $Root
    Labels   = $labels
    RowCount = $labels.Count
    Verified = $verified
    Message  = $null
}
