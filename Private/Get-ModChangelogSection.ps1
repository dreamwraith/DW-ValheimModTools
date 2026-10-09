#requires -Version 7

function Get-ModChangelogSection {
    [CmdletBinding()]
    param(
        [string]$ProjectDir,
        [string]$Version
    )

    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }

    $cleanVersion = if ($Version) { $Version -replace '^v', '' } else { "" }
    $clFile = Join-Path $ProjectDir "CHANGELOG.md"
    if (Test-Path $clFile) {
        $esc = [regex]::Escape($cleanVersion)
        $inSection = $false
        $lines = @(Get-Content -LiteralPath $clFile | Where-Object {
            if ($_ -match "^##\s+\[?$esc(\]|\s|$)") {
                $inSection = $true
                return $false
            }
            if ($inSection -and $_ -match "^##\s+") {
                $inSection = $false
            }
            $inSection
        })
        $result = ($lines -join "`n").Trim()
        if ($result) { return $result }
    }

    $notesFile = Join-Path $ProjectDir "bin\Publish\release_notes.md"
    if (Test-Path $notesFile) {
        $notes = (Get-Content -LiteralPath $notesFile -Raw).Trim()
        if ($notes) { return $notes }
    }

    return "Release version $cleanVersion"
}
