#requires -Version 7

$privateDir = Join-Path $PSScriptRoot "Private"
$publicDir  = Join-Path $PSScriptRoot "Public"

if (Test-Path $privateDir) {
    Get-ChildItem -Path $privateDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

if (Test-Path $publicDir) {
    Get-ChildItem -Path $publicDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

Export-ModuleMember -Function @(
    'New-ModPackage',
    'Invoke-ModRelease',
    'Publish-ModPackage',
    'Publish-ThunderstorePackage',
    'Publish-HexiumPackage',
    'Publish-NexusPackage'
)
