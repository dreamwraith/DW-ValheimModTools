#requires -Version 7

function New-ModArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Configuration = "Release"
    )

    $ProjectDir = $Context.ProjectDir
    $csprojPath = $Context.CsprojFile.FullName

    # 1. Create Distribution Archive with the Project's PackageMod Target
    # The target owns the package contents and syncs manifest.json. It packages the existing build output.
    $publishDir = Join-Path $ProjectDir "bin\Publish"
    $distZipPath = Join-Path $publishDir "$($Context.Name)-$Version.zip"
    if (Test-Path $distZipPath) { Remove-Item $distZipPath -Force }

    Write-Host "Running PackageMod target ($Configuration)..." -ForegroundColor Cyan
    dotnet msbuild $csprojPath -t:PackageMod -p:Configuration=$Configuration -nologo -v:minimal | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Error "PackageMod failed with exit code $LASTEXITCODE. Build project first or specify -Configuration."
        exit $LASTEXITCODE
    }
    if (-not (Test-Path $distZipPath)) {
        Write-Error "PackageMod did not create '$distZipPath'. The target must run for configuration '$Configuration'."
        exit 1
    }

    # 2. Expand Relative README Links for Portal Pages
    $readmePath = Join-Path $ProjectDir "README.md"
    if (Test-Path $readmePath) {
        # Resolve website URL for relative link expansion (matching Convert-MarkdownToBBCode)
        $webUrl = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "PackageProjectUrl")
        if (-not $webUrl) {
            $webUrl = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "RepositoryUrl")
        }
        if (-not $webUrl) {
            $manifestPath = Join-Path $ProjectDir "manifest.json"
            if (Test-Path $manifestPath) {
                try {
                    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                    $webUrl = $m.website_url
                } catch { }
            }
        }
        if ($webUrl -and $webUrl -match '^https?://github\.com/[^/]+/[^/]+') {
            $repoUrl = $Matches[0].TrimEnd('/')
            $readmeContent = [System.IO.File]::ReadAllText($readmePath)
            # Expand relative markdown links and badge links: [text](target) / [![alt](img)](target) -> absolute GitHub URLs
            $linkPattern = '\[((?:!\[[^\]]*\]\([^)]+\)|[^\]])+)\]\((?!https?://|mailto:|#)([^)\s]+)\)'
            $readmeContent = [regex]::Replace($readmeContent, $linkPattern, {
                param($m)
                $txt = $m.Groups[1].Value
                $target = $m.Groups[2].Value
                if ($target -match '^README\.md(#.+)$') {
                    return "[$txt]($repoUrl$($Matches[1]))"
                }
                return "[$txt]($repoUrl/blob/main/$target)"
            })

            $archive = [System.IO.Compression.ZipFile]::Open($distZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
            try {
                $archive.GetEntry("README.md").Delete()
                $writer = [System.IO.StreamWriter]::new($archive.CreateEntry("README.md").Open(), [System.Text.UTF8Encoding]::new($false))
                $writer.Write($readmeContent)
                $writer.Dispose()
            } finally {
                $archive.Dispose()
            }
        }
    } else {
        Write-Warning "Package asset 'README.md' not found in project root."
    }
    Write-Host "Created distribution package: $distZipPath" -ForegroundColor Green

    # 3. Extract Release Notes
    $changelogNotes = Get-ModChangelogSection -ProjectDir $ProjectDir -Version $Version
    $notesOut = Join-Path $publishDir "release_notes.md"
    Set-Content -Path $notesOut -Value $changelogNotes -Encoding utf8

    return [PSCustomObject]@{
        Name             = $Context.Name
        Version          = $Version
        PackagePath      = $distZipPath
        ReleaseNotesPath = $notesOut
    }
}
