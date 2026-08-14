<#
.SYNOPSIS
    Renders one or more JSON snippets stacked vertically as a VS Code dark-theme PNG.

.DESCRIPTION
    Used by the "Razor matrix" format to stack razor.deps.json targets sections
    (net10.0 on top, then net9.0, then net8.0) into a single image.

    Theme:
      * background        #1E1E1E
      * quoted strings    #CE9178  (keys AND values)
      * punctuation       #D4D4D4
      * indent guide      #404040
      * font              Consolas 14pt, line height = font height + 2

    No badge labels are drawn - the version numbers inside the JSON identify each snippet.

.PARAMETER Snippet
    One or more JSON strings, rendered top-to-bottom in the order supplied.

.PARAMETER OutputPath
    Full path of the PNG to write.

.EXAMPLE
    .\New-JsonSnippetImage.ps1 -Snippet $net10, $net9, $net8 -OutputPath .\razor-matrix.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Snippet,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\VsConfigInfo.Common.ps1"

$font        = [System.Drawing.Font]::new('Consolas', 14)
$fmt         = New-VsConfigStringFormat
# GDI+ trims leading spaces and pads each DrawString call, which corrupts both the
# indentation and the x-advance when a line is drawn as multiple coloured runs.
# Typographic format + explicit indent offsets avoid both problems.
$measureFmt  = [System.Drawing.StringFormat]::new([System.Drawing.StringFormat]::GenericTypographic)
$measureFmt.FormatFlags = $measureFmt.FormatFlags -bor
                          [System.Drawing.StringFormatFlags]::NoWrap -bor
                          [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
$measureFmt.Trimming = [System.Drawing.StringTrimming]::None

$lineHeight  = [int]$font.Height + 2
$margin      = 24
$guideInset  = 10
$snippetGap  = 28

$bg          = [System.Drawing.ColorTranslator]::FromHtml('#1E1E1E')
$stringColor = [System.Drawing.ColorTranslator]::FromHtml('#CE9178')
$punctColor  = [System.Drawing.ColorTranslator]::FromHtml('#D4D4D4')
$guideColor  = [System.Drawing.ColorTranslator]::FromHtml('#404040')

# Split a line into coloured runs: quoted strings vs everything else.
function Split-JsonLine {
    param([string]$Line)

    $runs = @()
    $pos  = 0
    foreach ($m in [regex]::Matches($Line, '"(?:[^"\\]|\\.)*"')) {
        if ($m.Index -gt $pos) {
            $runs += [pscustomobject]@{ Text = $Line.Substring($pos, $m.Index - $pos); IsString = $false }
        }
        $runs += [pscustomobject]@{ Text = $m.Value; IsString = $true }
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Line.Length) {
        $runs += [pscustomobject]@{ Text = $Line.Substring($pos); IsString = $false }
    }
    return $runs
}

$blocks = @()
foreach ($s in $Snippet) {
    $normalized = Format-JsonIndent -Json $s
    $lines = @($normalized -split "`r?`n")
    while ($lines.Count -gt 1 -and -not $lines[-1].Trim()) {
        $lines = $lines[0..($lines.Count - 2)]
    }
    $blocks += , $lines
}

# --- Measure ----------------------------------------------------------------
$probe = New-VsConfigBitmap -Width 1 -Height 1
try {
    # Consolas is monospaced, so one reference advance drives all indentation.
    $charWidth = $probe.Graphics.MeasureString(('0' * 20), $font, [int]::MaxValue, $measureFmt).Width / 20

    $maxWidth = 0
    foreach ($lines in $blocks) {
        foreach ($line in $lines) {
            $indent  = $line.Length - $line.TrimStart(' ').Length
            $trimmed = $line.TrimStart(' ')
            $w = ($indent * $charWidth) +
                 $probe.Graphics.MeasureString($trimmed, $font, [int]::MaxValue, $measureFmt).Width
            if ($w -gt $maxWidth) { $maxWidth = $w }
        }
    }
}
finally {
    $probe.Graphics.Dispose()
    $probe.Bitmap.Dispose()
}

$totalLines = ($blocks | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$width  = $margin + $guideInset + [int][Math]::Ceiling($maxWidth) + 2 + $margin
$height = ($margin * 2) + ($totalLines * $lineHeight) + (($blocks.Count - 1) * $snippetGap)

# --- Draw -------------------------------------------------------------------
$canvas      = New-VsConfigBitmap -Width $width -Height $height -Background $bg
$stringBrush = [System.Drawing.SolidBrush]::new($stringColor)
$punctBrush  = [System.Drawing.SolidBrush]::new($punctColor)
$guidePen    = [System.Drawing.Pen]::new($guideColor, 1)

$textX = $margin + $guideInset
$y     = $margin

for ($b = 0; $b -lt $blocks.Count; $b++) {
    $lines      = $blocks[$b]
    $blockTop   = $y
    $blockBottom = $y + ($lines.Count * $lineHeight)

    # Subtle vertical indent guide on the left edge of the snippet
    $canvas.Graphics.DrawLine($guidePen, $margin, $blockTop, $margin, $blockBottom)

    foreach ($line in $lines) {
        $indent  = $line.Length - $line.TrimStart(' ').Length
        $trimmed = $line.TrimStart(' ')
        $x = [single]($textX + ($indent * $charWidth))

        foreach ($run in (Split-JsonLine -Line $trimmed)) {
            $brush = if ($run.IsString) { $stringBrush } else { $punctBrush }
            $canvas.Graphics.DrawString($run.Text, $font, $brush,
                [System.Drawing.PointF]::new($x, [single]$y), $measureFmt)
            $x += $canvas.Graphics.MeasureString($run.Text, $font, [int]::MaxValue, $measureFmt).Width
        }
        $y += $lineHeight
    }

    if ($b -lt $blocks.Count - 1) { $y += $snippetGap }
}

$stringBrush.Dispose()
$punctBrush.Dispose()
$guidePen.Dispose()
$font.Dispose()
$fmt.Dispose()
$measureFmt.Dispose()

$saved = Save-VsConfigBitmap -Bitmap $canvas.Bitmap -Graphics $canvas.Graphics -Path $OutputPath

Write-Host ("[{0}] snippets={1} lines={2}" -f (Split-Path -Leaf $saved), $blocks.Count, $totalLines)

[pscustomobject]@{
    Path         = $saved
    SnippetCount = $blocks.Count
    LineCount    = $totalLines
    Width        = $width
    Height       = $height
}
