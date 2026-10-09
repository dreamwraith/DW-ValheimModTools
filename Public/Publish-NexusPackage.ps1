#requires -Version 7

function Publish-NexusPackage {
    [CmdletBinding()]
    param(
        [string]$PackagePath,
        [string]$ApiKey,
        [string]$ModId,
        [string]$FileId,
        [string]$Game = "valheim",
        [string]$Category = "main",
        [string]$Changelog,
        [string]$DisplayName,
        [string]$Description,
        [switch]$ArchiveExistingVersion,
        [switch]$NoUpdateModVersion,
        [switch]$NoSyncDescription,
        [switch]$NoSyncChangelog,
        [switch]$DryRun,
        [string]$ProjectDir
    )

    $ErrorActionPreference = "Stop"
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    if (-not $Game) { $Game = $env:NEXUSMODS_GAME ?? "valheim" }
    if (-not $Category) { $Category = "main" }

    if (-not $ApiKey) {
        $ApiKey = $env:NEXUSMODS_API_KEY ?? $env:NEXUS_API_KEY ?? [Environment]::GetEnvironmentVariable("NEXUSMODS_API_KEY", "User")
    }
    if (-not $ApiKey -and -not $DryRun) {
        Write-Error "No Nexus Mods API key found. Set NEXUSMODS_API_KEY or pass -ApiKey."
        exit 1
    }

    if (-not $ModId) {
        $ModId = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "NexusModId") ?? $env:NEXUSMODS_MOD_ID
    }
    if (-not $FileId) {
        $FileId = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "NexusFileId") ?? $env:NEXUSMODS_FILE_ID
    }

    if (-not $ModId) {
        $csprojName = (Get-ChildItem -Path $ProjectDir -Filter "*.csproj" | Select-Object -First 1).Name; if (-not $csprojName) { $csprojName = ".csproj" }
        Write-Warning "Nexus Mods publishing skipped: <NexusModId> is not configured in '$csprojName'. Add <NexusModId> to your .csproj once your mod page is created on Nexus Mods."
        return
    }

    if (-not $PackagePath) {
        $PackagePath = (Get-ChildItem (Join-Path $ProjectDir "bin\Publish") -Filter "*.zip" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notlike "*-Source.zip" } |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1).FullName
    }
    if (-not $PackagePath -or -not (Test-Path $PackagePath)) {
        Write-Error "Could not locate package zip. Run New-ModPackage first or specify -PackagePath."
        exit 1
    }

    # Extract name/version from manifest.json (project root or fallback to zip archive)
    $manifestPath = Join-Path $ProjectDir "manifest.json"
    $pkgName = "UnknownMod"
    $pkgVersion = "1.0.0"
    $pkgDesc = ""

    if (Test-Path $manifestPath) {
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $pkgName = $m.name; $pkgVersion = $m.version_number; $pkgDesc = $m.description
    } elseif ($PackagePath -and (Test-Path $PackagePath)) {
        try {
            $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
            $mEntry = $zipArchive.Entries | Where-Object { $_.Name -eq "manifest.json" } | Select-Object -First 1
            if ($mEntry) {
                $reader = [System.IO.StreamReader]::new($mEntry.Open())
                $m = $reader.ReadToEnd() | ConvertFrom-Json
                $pkgName = $m.name; $pkgVersion = $m.version_number; $pkgDesc = $m.description
                $reader.Dispose()
            }
            $zipArchive.Dispose()
        } catch { }
    }

    if (-not $DisplayName) { $DisplayName = "$pkgName $pkgVersion" }
    if (-not $Description) { $Description = $pkgDesc }
    if (-not $Changelog) { $Changelog = Get-ModChangelogSection -ProjectDir $ProjectDir -Version $pkgVersion }

    # Fallback to reading changelog from zip archive if not found on disk
    if ((-not $Changelog -or $Changelog -like "Release version *") -and $PackagePath -and (Test-Path $PackagePath)) {
        try {
            $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
            $clEntry = $zipArchive.Entries | Where-Object { $_.Name -eq "CHANGELOG.md" } | Select-Object -First 1
            if ($clEntry) {
                $reader = [System.IO.StreamReader]::new($clEntry.Open())
                $clRaw = $reader.ReadToEnd()
                $reader.Dispose()
                $cleanVer = $pkgVersion -replace '^v', ''
                $esc = [regex]::Escape($cleanVer)
                $lines = $clRaw -split "`n"
                $inSec = $false
                $excerpt = [System.Collections.Generic.List[string]]::new()
                foreach ($line in $lines) {
                    if ($line -match "^##\s+\[?$esc(\]|\s|$)") { $inSec = $true; continue }
                    if ($inSec) {
                        if ($line -match "^##\s+") { break }
                        $excerpt.Add($line)
                    }
                }
                $extracted = ($excerpt -join "`n").Trim()
                if ($extracted) { $Changelog = $extracted }
            }
            $zipArchive.Dispose()
        } catch { }
    }

    $baseUrl = $env:NEXUSMODS_API_BASE ? $env:NEXUSMODS_API_BASE.TrimEnd('/') : "https://api.nexusmods.com/v3"
    $dispFile = $FileId ? $FileId : "[Auto-detect from Nexus Mods]"
    Write-Host "Package verified: $pkgName v$pkgVersion (Game: $Game | Mod: $ModId | File: $dispFile)" -ForegroundColor Green

    if ($DryRun) {
        Write-Host "[DryRun] Package structure valid. Target endpoint: $baseUrl (Game: $Game, Mod: $ModId, File: $dispFile)" -ForegroundColor Yellow
        if (-not $NoSyncChangelog -and $Changelog) {
            $cleanVersion = $pkgVersion -replace '^v', ''
            Write-Host "[DryRun] Would append changelog entries to Nexus Mods (POST $baseUrl/mods/$ModId/changelogs for version $cleanVersion)" -ForegroundColor Yellow
        }
        if (-not $NoSyncDescription) {
            $readmePath = Join-Path $ProjectDir "README.md"
            if (Test-Path $readmePath) {
                $bbcodeDesc = Convert-MarkdownToBBCode -MarkdownPath $readmePath -ProjectDir $ProjectDir
                Write-Host "[DryRun] Would update mod details on Nexus Mods (PATCH $baseUrl/mods/$ModId):" -ForegroundColor Yellow
                if ($Description) {
                    $modSummary = ($Description -replace '\s+', ' ').Trim()
                    if ($modSummary.Length -gt 350) { $modSummary = $modSummary.Substring(0, 347) + "..." }
                    Write-Host "[DryRun]   Summary: $modSummary" -ForegroundColor Yellow
                }
                Write-Host "[DryRun]   Description: Converted BBCode ($($bbcodeDesc.Length) chars)" -ForegroundColor Yellow
            }
        }
        return
    }

    Write-Host "Uploading $pkgName v$pkgVersion to Nexus Mods ($Game / Mod ID: $ModId)..." -ForegroundColor Cyan
    $headers = @{ "apikey" = $ApiKey; "User-Agent" = "DW-ModTools-Publisher" }

    try {
        # Resolve game-scoped ID (e.g. 4329) to global Mod ID (e.g. 15749645078761)
        $globalModId = $ModId
        try {
            $modInfo = Invoke-RestMethod -Uri "$baseUrl/games/$Game/mods/$ModId" -Headers $headers
            if ($modInfo.data.id) {
                $globalModId = $modInfo.data.id
            }
        } catch { }

        if (-not $FileId) {
            Write-Host "Auto-resolving update chain for Mod $ModId..." -ForegroundColor Cyan
            $files = Invoke-RestMethod -Uri "$baseUrl/mods/$globalModId/files" -Headers $headers
            $filesList = $files.data.mod_files
            $targetFile = ($filesList | Where-Object { $_.is_active } | Select-Object -First 1) ?? ($filesList | Select-Object -First 1)

            if ($targetFile -and $targetFile.id) {
                $FileId = $targetFile.id
                Write-Host "Target update chain resolved: File ID $FileId ('$($targetFile.name)')" -ForegroundColor DarkGreen
            } else {
                Write-Error "Could not auto-resolve target file ID for Mod $ModId. Specify -FileId."
                exit 1
            }
        }

        # S3 Multipart Upload
        $fileBytes = [System.IO.File]::ReadAllBytes($PackagePath)
        $initBody = @{ filename = [System.IO.Path]::GetFileName($PackagePath); size_bytes = [string]$fileBytes.Length } | ConvertTo-Json
        $init = Invoke-RestMethod -Uri "$baseUrl/uploads/multipart" -Method Post -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $initBody
        $upload = $init.data ? $init.data : $init

        $partSize = [int64]$upload.part_size_bytes
        $totalParts = $upload.part_presigned_urls.Count
        $completedParts = [System.Collections.Generic.List[object]]::new()

        for ($i = 0; $i -lt $totalParts; $i++) {
            $partNum = $i + 1
            $offset = [int64]$i * $partSize
            $len = [Math]::Min($partSize, $fileBytes.Length - $offset)
            $chunk = [byte[]]::new($len)
            [System.Buffer]::BlockCopy($fileBytes, [int]$offset, $chunk, 0, [int]$len)

            Write-Host "Uploading part $partNum/$totalParts ($len bytes)..." -ForegroundColor Cyan
            $put = Invoke-WebRequest -Uri $upload.part_presigned_urls[$i] -Method Put -Body $chunk -Headers @{ "Content-Type" = "application/octet-stream" }
            $rawEtag = $put.Headers.ETag ? $put.Headers.ETag : $put.Headers["ETag"]
            if ($rawEtag -is [array]) { $rawEtag = $rawEtag[0] }
            $completedParts.Add(@{ PartNumber = $partNum; ETag = ($rawEtag ? $rawEtag.Trim('"') : "part-$partNum") })
        }

        $xmlParts = ($completedParts | ForEach-Object { "  <Part><PartNumber>$($_.PartNumber)</PartNumber><ETag>$($_.ETag)</ETag></Part>" }) -join "`n"
        Invoke-WebRequest -Uri $upload.complete_presigned_url -Method Post -Headers @{ "Content-Type" = "application/xml" } -Body "<CompleteMultipartUpload>`n$xmlParts`n</CompleteMultipartUpload>" | Out-Null

        Invoke-RestMethod -Uri "$baseUrl/uploads/$($upload.id)/finalise" -Method Post -Headers $headers | Out-Null
        Write-Host "Waiting for Nexus Mods to verify archive..." -ForegroundColor Cyan
        $isAvailable = $false
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            Start-Sleep -Seconds 2
            $poll = Invoke-RestMethod -Uri "$baseUrl/uploads/$($upload.id)" -Headers $headers
            $state = $poll.data ? $poll.data.state : $poll.state
            if ($state -eq "available") { $isAvailable = $true; break }
        }
        if (-not $isAvailable) { Write-Error "Upload processing timed out waiting for state 'available'."; exit 1 }

        $verBody = [ordered]@{
            upload_id                    = $upload.id
            name                         = $DisplayName
            description                  = $Description
            version                      = $pkgVersion
            file_category                = $Category
            archive_existing_file        = [bool]$ArchiveExistingVersion
            primary_mod_manager_download = $true
            allow_mod_manager_download   = $true
            update_mod_version           = (-not $NoUpdateModVersion)
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "$baseUrl/mod-files/$FileId/versions" -Method Post -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $verBody | Out-Null

        # Sync Changelog (POST /v3/mods/{id}/changelogs - addModChangelogEntries)
        if (-not $NoSyncChangelog -and $Changelog) {
            $cleanVersion = $pkgVersion -replace '^v', ''
            Write-Host "`n>> Syncing changelog to Nexus Mods for version $cleanVersion..." -ForegroundColor Cyan
            $clBody = @{
                version   = $cleanVersion
                changelog = $Changelog
            } | ConvertTo-Json

            try {
                Invoke-RestMethod -Uri "$baseUrl/mods/$globalModId/changelogs" `
                    -Method Post `
                    -Headers ($headers + @{ "Content-Type" = "application/json" }) `
                    -Body $clBody | Out-Null
                Write-Host "[OK] Changelog updated on Nexus Mods for version $cleanVersion." -ForegroundColor DarkGreen
            } catch {
                $clErr = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
                Write-Warning "Could not update changelog on Nexus Mods: $clErr"
            }
        }

        # Sync Mod Page Description and Summary (PATCH /v3/mods/{id})
        if (-not $NoSyncDescription) {
            $readmePath = Join-Path $ProjectDir "README.md"
            if (Test-Path $readmePath) {
                Write-Host "`n>> Syncing mod page description & summary to Nexus Mods..." -ForegroundColor Cyan
                $bbcodeDesc = Convert-MarkdownToBBCode -MarkdownPath $readmePath -ProjectDir $ProjectDir

                $modSummary = $null
                if ($Description) {
                    $modSummary = ($Description -replace '\s+', ' ').Trim()
                    if ($modSummary.Length -gt 350) {
                        $modSummary = $modSummary.Substring(0, 347) + "..."
                    }
                }

                if ($bbcodeDesc) {
                    $patchBody = [ordered]@{
                        description = $bbcodeDesc
                    }
                    if ($modSummary) {
                        $patchBody["summary"] = $modSummary
                    }
                    $patchJson = $patchBody | ConvertTo-Json -Depth 5
                    try {
                        Invoke-RestMethod -Uri "$baseUrl/mods/$globalModId" -Method Patch -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $patchJson | Out-Null
                        Write-Host "[OK] Mod page description and summary updated on Nexus Mods." -ForegroundColor DarkGreen
                    } catch {
                        $pErr = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
                        Write-Warning "Could not update mod description on Nexus Mods: $pErr"
                    }
                }
            }
        }

        Write-Host "`nSuccessfully published to Nexus Mods!" -ForegroundColor Green
        Write-Host "Mod URL: https://www.nexusmods.com/$Game/mods/${ModId}?tab=files" -ForegroundColor Cyan
    } catch {
        $errMsg = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Error "Nexus Mods upload failed:`n$errMsg"
        exit 1
    }
}
