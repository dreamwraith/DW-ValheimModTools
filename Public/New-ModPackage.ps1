#requires -Version 7

function New-ModPackage {
    [CmdletBinding()]
    param(
        [ValidateSet("Patch", "Minor", "Major")]
        [string]$Bump,

        [string]$SetVersion,

        [string]$Configuration = "Release",

        [string]$ProjectDir
    )

    $ErrorActionPreference = "Stop"
    $ProgressPreference = "SilentlyContinue"

    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    if (-not $Configuration) { $Configuration = "Release" }

    $ctx = Get-ModProjectContext -ProjectDir $ProjectDir
    if (-not $ctx) { exit 1 }

    $version = Resolve-ModVersion -CurrentVersion $ctx.Version -Bump $Bump -SetVersion $SetVersion
    if ($version -ne $ctx.Version) {
        Set-ModProjectVersion -Context $ctx -Version $version
    } else {
        Write-Host "Using existing project version: $version (from $($ctx.CsprojFile.Name))" -ForegroundColor Cyan
    }

    # Always compile first, so the zip never holds a DLL older than its manifest
    Invoke-ModBuild -ProjectDir $ProjectDir -Configuration $Configuration
    return New-ModArchive -Context $ctx -Version $version -Configuration $Configuration
}
