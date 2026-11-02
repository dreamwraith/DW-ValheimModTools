#requires -Version 7

function Set-ModProjectVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $csproj = $Context.CsprojXml
    Write-Host "Updating version: $($Context.Version) -> $Version in $($Context.CsprojFile.Name)" -ForegroundColor Cyan
    $versionNode = $csproj.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1
    if ($versionNode) {
        $versionNode.Version = $Version
    } else {
        $firstGroup = $csproj.Project.PropertyGroup | Select-Object -First 1
        $elem = $csproj.CreateElement("Version")
        $elem.InnerText = $Version
        $firstGroup.AppendChild($elem) | Out-Null
    }
    $csproj.Save($Context.CsprojFile.FullName)
}
