#requires -Version 7

function Set-ModProjectVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $csprojPath = $Context.CsprojFile.FullName
    Write-Host "Updating version: $($Context.Version) -> $Version in $($Context.CsprojFile.Name)" -ForegroundColor Cyan

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $rawContent = [System.IO.File]::ReadAllText($csprojPath, [System.Text.Encoding]::UTF8) -replace "\r\n?", "`n"
    $escapedVersion = [System.Security.SecurityElement]::Escape($Version).Replace('$', '$$')

    $versionPattern = [regex]::new('(<Version>)([^<]*)(</Version>)')
    if ($versionPattern.IsMatch($rawContent)) {
        $updatedContent = $versionPattern.Replace($rawContent, "`${1}$escapedVersion`${3}", 1)
    } else {
        $groupEndPattern = [regex]::new('([ \t]*</PropertyGroup>)')
        if (-not $groupEndPattern.IsMatch($rawContent)) {
            throw "No <PropertyGroup> found in '$csprojPath'."
        }
        $updatedContent = $groupEndPattern.Replace($rawContent, "    <Version>$escapedVersion</Version>`n`${1}", 1)
    }

    if (-not $updatedContent.EndsWith("`n")) {
        $updatedContent += "`n"
    }

    [System.IO.File]::WriteAllText($csprojPath, $updatedContent, $utf8NoBom)
    $Context.Version = $Version
    $Context.CsprojXml = [xml]$updatedContent
}
