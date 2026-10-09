#requires -Version 7

function Get-ModProjectProperty {
    [CmdletBinding()]
    param(
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$Property
    )

    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    $csproj = Get-ChildItem -Path $ProjectDir -Filter "*.csproj" | Select-Object -First 1
    $csprojUser = Get-ChildItem -Path $ProjectDir -Filter "*.csproj.user" | Select-Object -First 1

    foreach ($file in @($csprojUser, $csproj)) {
        if ($file -and (Test-Path $file.FullName)) {
            try {
                $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw)
                $node = $xml.Project.PropertyGroup | Where-Object { $_.$Property } | Select-Object -First 1
                if ($node) {
                    $val = $node.$Property
                    if ($val -and $val.Trim()) { return $val.Trim() }
                }
            } catch { }
        }
    }
    return $null
}

function Get-ModProjectContext {
    [CmdletBinding()]
    param(
        [string]$ProjectDir
    )

    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    $csproj = Get-ChildItem -Path $ProjectDir -Filter "*.csproj" | Select-Object -First 1
    if (-not $csproj) {
        Write-Error "No .csproj file found in '$ProjectDir'."
        return $null
    }

    $xml = [xml](Get-Content -LiteralPath $csproj.FullName -Raw)
    $name = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Product") ??
            (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "PackageId") ??
            (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "AssemblyName") ??
            $csproj.BaseName

    $version = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Version") ?? "1.0.0"
    $authors = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Authors") ?? "DreamWraith"
    $desc = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Description") ?? ""
    $nexusModId = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "NexusModId")
    $nexusFileId = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "NexusFileId")

    return [PSCustomObject]@{
        ProjectDir  = $ProjectDir
        CsprojFile  = $csproj
        CsprojXml   = $xml
        Name        = $name
        Version     = $version
        Authors     = $authors
        Description = $desc
        NexusModId  = $nexusModId
        NexusFileId = $nexusFileId
    }
}
