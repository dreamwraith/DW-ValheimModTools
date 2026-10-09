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

    $csprojPath = $ctx.CsprojFile.FullName
    $csproj = $ctx.CsprojXml
    $currentVersion = $ctx.Version
    $newVersion = $null

    # 1. Version Bumping
    if ($SetVersion) {
        $newVersion = $SetVersion
    } elseif ($Bump) {
        $parts = $currentVersion.Split('.')
        [int]$major = ($parts.Length -gt 0) ? [int]$parts[0] : 1
        [int]$minor = ($parts.Length -gt 1) ? [int]$parts[1] : 0
        [int]$patch = ($parts.Length -gt 2) ? [int]$parts[2] : 0

        switch ($Bump) {
            "Major" { $major++; $minor = 0; $patch = 0 }
            "Minor" { $minor++; $patch = 0 }
            "Patch" { $patch++ }
        }
        $newVersion = "$major.$minor.$patch"
    }

    if ($newVersion -and $newVersion -ne $currentVersion) {
        Write-Host "Updating version: $currentVersion -> $newVersion in $($ctx.CsprojFile.Name)" -ForegroundColor Cyan
        $versionNode = $csproj.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1
        if ($versionNode) {
            $versionNode.Version = $newVersion
        } else {
            $firstGroup = $csproj.Project.PropertyGroup | Select-Object -First 1
            $elem = $csproj.CreateElement("Version")
            $elem.InnerText = $newVersion
            $firstGroup.AppendChild($elem) | Out-Null
        }
        $csproj.Save($csprojPath)
        $currentVersion = $newVersion
    } else {
        Write-Host "Using existing project version: $currentVersion (from $($ctx.CsprojFile.Name))" -ForegroundColor Cyan
    }

    # 2. Sync manifest.json
    $manifestPath = Join-Path $ProjectDir "manifest.json"
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.version_number = $currentVersion
        if (-not $manifest.name) { $manifest.name = $ctx.Name }
        if (-not $manifest.description) { $manifest.description = $ctx.Description }
        $webUrl = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "PackageProjectUrl")
        if ($webUrl) { $manifest.website_url = $webUrl }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding utf8
        Write-Host "Synchronized manifest.json with version $currentVersion" -ForegroundColor Green
    }

    # 3. Setup Publishing Output Directories
    $publishDir = Join-Path $ProjectDir "bin\Publish"
    $stagingDir = Join-Path $publishDir "staging"
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

    # 4. Copy Mod Assembly & Dependencies
    $binDir = Join-Path $ProjectDir "bin\$Configuration"
    $mainDll = Get-ChildItem -Path $binDir -Filter "$($ctx.Name).dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $mainDll) {
        $mainDll = Get-ChildItem -Path $binDir -Filter "*.dll" -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notlike "System.*" -and $_.Name -notlike "Microsoft.*" -and $_.Name -notlike "0Harmony*" } |
                   Select-Object -First 1
    }

    if (-not $mainDll) {
        Write-Error "Could not find built assembly in '$binDir'. Build project first or specify -Configuration."
        exit 1
    }

    $buildOutDir = $mainDll.DirectoryName
    Write-Host "Staging build artifacts from $buildOutDir..." -ForegroundColor Cyan

    $ignoredDlls = @("0Harmony.dll", "assembly_valheim.dll", "assembly_guiutils.dll", "UnityEngine.dll")
    Get-ChildItem -Path $buildOutDir -File | Where-Object {
        $ext = $_.Extension.ToLower()
        ($ext -eq ".dll" -and $_.Name -notmatch "^(System\.|Microsoft\.)" -and $_.Name -notin $ignoredDlls)
    } | Copy-Item -Destination $stagingDir -Force

    # 5. Copy Package Assets
    foreach ($asset in @("icon.png", "README.md", "manifest.json", "CHANGELOG.md")) {
        $src = Join-Path $ProjectDir $asset
        if (Test-Path $src) {
            Copy-Item $src -Destination $stagingDir -Force
        } else {
            Write-Warning "Package asset '$asset' not found in project root."
        }
    }

    # 6. Create Distribution Archive
    $distZipPath = Join-Path $publishDir "$($ctx.Name)-$currentVersion.zip"
    if (Test-Path $distZipPath) { Remove-Item $distZipPath -Force }
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $distZipPath -Force
    Remove-Item $stagingDir -Recurse -Force
    Write-Host "Created distribution package: $distZipPath" -ForegroundColor Green

    # 7. Extract Release Notes
    $changelogNotes = Get-ModChangelogSection -ProjectDir $ProjectDir -Version $currentVersion
    $notesOut = Join-Path $publishDir "release_notes.md"
    Set-Content -Path $notesOut -Value $changelogNotes -Encoding utf8

    return [PSCustomObject]@{
        Name             = $ctx.Name
        Version          = $currentVersion
        PackagePath      = $distZipPath
        ReleaseNotesPath = $notesOut
    }
}
