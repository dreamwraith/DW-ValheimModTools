#requires -Version 7

function Invoke-ModRelease {
    [CmdletBinding()]
    param(
        [ValidateSet("Patch", "Minor", "Major")]
        [string]$Bump,

        [string]$SetVersion,

        [string]$Configuration = "Release",

        [switch]$Publish,

        [switch]$NoDraft,

        [switch]$DryRun,

        [string]$ProjectDir
    )

    $ErrorActionPreference = "Stop"
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    if (-not $Configuration) { $Configuration = "Release" }

    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Mod Release Coordinator ($Configuration)" -ForegroundColor Cyan
    Write-Host "==========================================================`n" -ForegroundColor Cyan

    # Check gh CLI
    if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI ('gh') is not installed or not in PATH. Install from https://cli.github.com/"
        exit 1
    }

    # Step 1: Version Synchronization (if bumping version, bump BEFORE compiling so DLL has updated metadata)
    if ($Bump -or $SetVersion) {
        Write-Host "[Step 1/5] Updating project version ($($Bump ? "Bump $Bump" : "Set $SetVersion"))..." -ForegroundColor Cyan
        $bumpPkg = New-ModPackage -Bump $Bump -SetVersion $SetVersion -Configuration $Configuration -ProjectDir $ProjectDir
        $ver = $bumpPkg.Version
    } else {
        $ctx = Get-ModProjectContext -ProjectDir $ProjectDir
        $ver = $ctx.Version
        Write-Host "[Step 1/5] Using project version v$ver..." -ForegroundColor Cyan
    }

    $tag = "v$ver"

    # Step 2: Compile Solution
    Write-Host "`n[Step 2/5] Compiling solution in $Configuration mode for $tag..." -ForegroundColor Cyan
    dotnet build (Join-Path $ProjectDir "") -c $Configuration
    if ($LASTEXITCODE -ne 0) { Write-Error "Build failed with exit code $LASTEXITCODE."; exit $LASTEXITCODE }

    # Step 3: Package Mod Distribution Archive
    Write-Host "`n[Step 3/5] Packaging distribution archive..." -ForegroundColor Cyan
    $pkg = New-ModPackage -Configuration $Configuration -ProjectDir $ProjectDir

    # Step 4: Synchronize GitHub Secrets and Variables
    Write-Host "`n[Step 4/5] Synchronizing repository secrets & variables..." -ForegroundColor Cyan
    $tToken = $env:THUNDERSTORE_TOKEN ?? [Environment]::GetEnvironmentVariable("THUNDERSTORE_TOKEN", "User")
    $hToken = $env:HEXIUM_TOKEN ?? [Environment]::GetEnvironmentVariable("HEXIUM_TOKEN", "User")
    $nKey   = $env:NEXUSMODS_API_KEY ?? $env:NEXUS_API_KEY ?? [Environment]::GetEnvironmentVariable("NEXUSMODS_API_KEY", "User")
    $cNamespace = $env:COMMUNITY_NAMESPACE ?? [Environment]::GetEnvironmentVariable("COMMUNITY_NAMESPACE", "User") ?? (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Authors")

    if ($tToken) { gh secret set THUNDERSTORE_TOKEN --body "$tToken" 2>$null }
    if ($hToken) { gh secret set HEXIUM_TOKEN --body "$hToken" 2>$null }
    if ($nKey)   { gh secret set NEXUSMODS_API_KEY --body "$nKey" 2>$null }
    if ($cNamespace) { gh variable set COMMUNITY_NAMESPACE --body "$cNamespace" 2>$null }

    # Changelog notes
    $notes = Get-ModChangelogSection -ProjectDir $ProjectDir -Version $ver

    # Step 5: GitHub Release Creation
    Write-Host "`n[Step 5/5] Preparing GitHub Release for $tag..." -ForegroundColor Cyan
    $isDraft = (-not $Publish -and -not $NoDraft)
    $draftFlag = $isDraft ? @("--draft") : @()

    $assets = @($pkg.PackagePath)

    if ($DryRun) {
        Write-Host "[DryRun] Would execute: gh release create $tag $($assets -join ' ') --title `"$tag`" $draftFlag" -ForegroundColor Yellow
        return
    }

    # Check existing release
    $existing = (gh release view $tag --json tagName 2>$null | ConvertFrom-Json)
    if ($existing -and $existing.tagName) {
        Write-Host "Updating existing GitHub release $tag..." -ForegroundColor Cyan
        gh release upload $tag @assets --clobber
    } else {
        Write-Host "Creating new GitHub release $tag ($($isDraft ? 'Draft' : 'Published'))..." -ForegroundColor Cyan
        gh release create $tag @assets --title "$tag" --notes "$notes" @draftFlag
    }

    Write-Host "`nRelease complete for $tag!" -ForegroundColor Green
    if ($isDraft) {
        Write-Host "Release created as DRAFT on GitHub. Review assets and publish when ready to trigger portal deployments." -ForegroundColor Yellow
    } else {
        Write-Host "Release PUBLISHED on GitHub. CI workflows will deploy to portals." -ForegroundColor Green
    }
}
