#requires -Version 7

function Resolve-ModVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [string]$Bump,

        [string]$SetVersion
    )

    if ($SetVersion) { return $SetVersion }
    if (-not $Bump) { return $CurrentVersion }

    $parts = $CurrentVersion.Split('.')
    [int]$major = ($parts.Length -gt 0) ? [int]$parts[0] : 1
    [int]$minor = ($parts.Length -gt 1) ? [int]$parts[1] : 0
    [int]$patch = ($parts.Length -gt 2) ? [int]$parts[2] : 0

    switch ($Bump) {
        "Major" { $major++; $minor = 0; $patch = 0 }
        "Minor" { $minor++; $patch = 0 }
        "Patch" { $patch++ }
    }

    return "$major.$minor.$patch"
}
