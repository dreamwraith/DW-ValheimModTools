#requires -Version 7

function Publish-ThunderstorePackage {
    [CmdletBinding()]
    param(
        [string]$PackagePath,
        [string]$Token,
        [string]$Community = "valheim",
        [string]$Namespace,
        [string[]]$Categories,
        [switch]$DryRun,
        [string]$ProjectDir
    )

    $ErrorActionPreference = "Stop"
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    if (-not $Community) { $Community = $env:COMMUNITY ?? "valheim" }

    if (-not $Token) {
        $Token = $env:THUNDERSTORE_TOKEN ?? [Environment]::GetEnvironmentVariable("THUNDERSTORE_TOKEN", "User")
    }
    if (-not $Token -and -not $DryRun) {
        Write-Error "No Thunderstore token provided. Set THUNDERSTORE_TOKEN or pass -Token."
        exit 1
    }

    if (-not $Namespace) {
        $Namespace = $env:COMMUNITY_NAMESPACE ?? [Environment]::GetEnvironmentVariable("COMMUNITY_NAMESPACE", "User") ?? (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "Authors")
    }
    if (-not $Namespace -and -not $DryRun) {
        Write-Error "No author/team namespace found. Set COMMUNITY_NAMESPACE, pass -Namespace, or set <Authors> in .csproj."
        exit 1
    }

    if (-not $Categories -or $Categories.Count -eq 0) {
        $Categories = ($env:MOD_CATEGORIES ? ($env:MOD_CATEGORIES -split ',') : @("mods"))
    }

    if (-not $PackagePath) {
        $PackagePath = (Get-ChildItem -Path (Join-Path $ProjectDir "bin\Publish") -Filter "*.zip" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notlike "*-Source.zip" } |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1).FullName
    }

    if (-not $PackagePath -or -not (Test-Path $PackagePath)) {
        Write-Error "Could not locate package zip. Run New-ModPackage first or specify -PackagePath."
        exit 1
    }

    # Validate Zip & Manifest
    $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    $manifestEntry = $zipArchive.Entries | Where-Object { $_.Name -eq "manifest.json" } | Select-Object -First 1
    if (-not $manifestEntry) {
        $zipArchive.Dispose()
        Write-Error "Package is missing manifest.json."
        exit 1
    }
    $reader = [System.IO.StreamReader]::new($manifestEntry.Open())
    $manifestContent = $reader.ReadToEnd()
    $reader.Dispose()
    $zipArchive.Dispose()

    $manifest = $manifestContent | ConvertFrom-Json
    $pkgName = $manifest.name
    $pkgVersion = $manifest.version_number
    $baseUrl = $env:THUNDERSTORE_API_BASE ? $env:THUNDERSTORE_API_BASE.TrimEnd('/') : "https://thunderstore.io/api/experimental"

    Write-Host "Package verified: $Namespace/$pkgName v$pkgVersion (Community: $Community)" -ForegroundColor Green

    if ($DryRun) {
        Write-Host "[DryRun] Package structure valid. Target endpoint: $baseUrl/submission/upload/" -ForegroundColor Yellow
        return
    }

    Write-Host "Submitting $Namespace/$pkgName v$pkgVersion to Thunderstore ($Community)..." -ForegroundColor Cyan
    $form = @{
        file = Get-Item $PackagePath
        metadata = @{
            author_name      = $Namespace
            communities      = @($Community)
            categories       = @($Categories)
            has_nsfw_content = $false
        } | ConvertTo-Json
    }

    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/submission/upload/" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $Token"; "User-Agent" = "DW-ModTools-Publisher" } `
            -Form $form

        Write-Host "`nSuccessfully published to Thunderstore!" -ForegroundColor Green
        Write-Host "Mod URL: https://thunderstore.io/c/$Community/p/$Namespace/$pkgName/" -ForegroundColor Cyan
    } catch {
        $errMsg = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Error "Thunderstore upload failed:`n$errMsg"
        exit 1
    }
}
