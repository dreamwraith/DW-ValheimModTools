#requires -Version 7

function Publish-ModPackage {
    [CmdletBinding()]
    param(
        [ValidateSet("All", "Thunderstore", "Hexium", "Nexus")]
        [string]$Target = "All",

        [string]$PackagePath,
        [string]$Configuration = "Release",
        [switch]$NoBuild,
        [switch]$DryRun,
        [string]$ProjectDir,

        # Pass-through overrides
        [string]$ThunderstoreToken,
        [string]$HexiumToken,
        [string]$NexusApiKey,
        [string]$NexusModId,
        [string]$NexusFileId,
        [string]$Community,
        [string]$Namespace
    )

    $ErrorActionPreference = "Stop"
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    if (-not $Target) { $Target = "All" }
    if (-not $Configuration) { $Configuration = "Release" }

    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Mod Publisher -> Target: $Target ($Configuration)" -ForegroundColor Cyan
    Write-Host "==========================================================`n" -ForegroundColor Cyan

    if (-not $NoBuild) {
        Write-Host "[Step 1/3] Building solution in $Configuration mode..." -ForegroundColor Cyan
        dotnet build (Join-Path $ProjectDir "") -c $Configuration
        if ($LASTEXITCODE -ne 0) { Write-Error "Build failed with exit code $LASTEXITCODE."; exit $LASTEXITCODE }
    } else {
        Write-Host "[Step 1/3] Skipping build (-NoBuild specified)." -ForegroundColor Yellow
    }

    if (-not $PackagePath) {
        Write-Host "`n[Step 2/3] Resolving distribution package..." -ForegroundColor Cyan
        $pkg = New-ModPackage -Configuration $Configuration -ProjectDir $ProjectDir
        $PackagePath = $pkg.PackagePath
    } else {
        Write-Host "`n[Step 2/3] Using specified package: $PackagePath" -ForegroundColor Cyan
    }

    $pkgName = [System.IO.Path]::GetFileName($PackagePath)
    Write-Host "`n[Step 3/3] Publishing package: $pkgName" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "[DRY RUN MODE ENABLED - No actual network uploads will be made]`n" -ForegroundColor Yellow
    }

    $results = [ordered]@{}

    # Thunderstore
    if ($Target -in @("All", "Thunderstore")) {
        Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
        Write-Host ">> Publishing to Thunderstore..." -ForegroundColor Cyan
        try {
            Publish-ThunderstorePackage -PackagePath $PackagePath -Token $ThunderstoreToken -Community ($Community ?? "valheim") -Namespace $Namespace -ProjectDir $ProjectDir -DryRun:$DryRun
            $results["Thunderstore"] = "Success"
        } catch {
            $results["Thunderstore"] = "Failed: $($_.Exception.Message)"
            Write-Warning "Thunderstore submission failed: $($_.Exception.Message)"
        }
    }

    # Hexium
    if ($Target -in @("All", "Hexium")) {
        Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
        Write-Host ">> Publishing to Hexium..." -ForegroundColor Cyan
        try {
            Publish-HexiumPackage -PackagePath $PackagePath -Token $HexiumToken -Community ($Community ?? "valheim") -Namespace $Namespace -ProjectDir $ProjectDir -DryRun:$DryRun
            $results["Hexium"] = "Success"
        } catch {
            $results["Hexium"] = "Failed: $($_.Exception.Message)"
            Write-Warning "Hexium submission failed: $($_.Exception.Message)"
        }
    }

    # Nexus Mods
    if ($Target -in @("All", "Nexus")) {
        Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
        Write-Host ">> Publishing to Nexus Mods..." -ForegroundColor Cyan
        try {
            $checkModId = if ($NexusModId) { $NexusModId } else { (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "NexusModId") ?? $env:NEXUSMODS_MOD_ID }
            if (-not $checkModId -and $Target -eq "All") {
                Publish-NexusPackage -PackagePath $PackagePath -ApiKey $NexusApiKey -ModId $NexusModId -FileId $NexusFileId -Game ($Community ?? "valheim") -ProjectDir $ProjectDir -DryRun:$DryRun
                $results["Nexus Mods"] = "Skipped (No <NexusModId>)"
            } else {
                Publish-NexusPackage -PackagePath $PackagePath -ApiKey $NexusApiKey -ModId $NexusModId -FileId $NexusFileId -Game ($Community ?? "valheim") -ProjectDir $ProjectDir -DryRun:$DryRun
                $results["Nexus Mods"] = "Success"
            }
        } catch {
            $results["Nexus Mods"] = "Failed: $($_.Exception.Message)"
            Write-Warning "Nexus Mods submission failed: $($_.Exception.Message)"
        }
    }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host " Publication Summary" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    foreach ($k in $results.Keys) {
        $color = ($results[$k] -eq "Success") ? "Green" : (($results[$k] -like "Skipped*") ? "Yellow" : "Red")
        Write-Host " - $k : $($results[$k])" -ForegroundColor $color
    }
    Write-Host "==========================================================`n" -ForegroundColor Cyan
}

