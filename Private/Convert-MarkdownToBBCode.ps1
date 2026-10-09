#requires -Version 7

function Convert-MarkdownToBBCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath,

        [string]$ProjectDir
    )

    if (-not (Test-Path $MarkdownPath)) {
        Write-Error "Markdown file '$MarkdownPath' not found."
        return $null
    }

    # Resolve tool from user cache in .tools directory
    $cacheBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME ".cache" }
    $toolDir   = Join-Path $cacheBase "DW-ValheimModTools\.tools\Converter.MarkdownToBBCodeNM"
    $toolDll   = Join-Path $toolDir "Converter.MarkdownToBBCodeNM.Tool.dll"

    if (-not (Test-Path $toolDll)) {
        Write-Host "Downloading Converter.MarkdownToBBCodeNM tool from NuGet..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
        $nupkgUrl = "https://www.nuget.org/api/v2/package/Converter.MarkdownToBBCodeNM.Tool/1.0.0.29"
        $tempZip = Join-Path $toolDir ".package.zip"
        try {
            Invoke-WebRequest -Uri $nupkgUrl -OutFile $tempZip
            $tempExtract = Join-Path $toolDir ".temp_extract"
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

            $net8Dir = Join-Path $tempExtract "tools\net8.0\any"
            if (Test-Path $net8Dir) {
                Get-ChildItem -Path $net8Dir | Copy-Item -Destination $toolDir -Force
            }
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Error "Failed to download Converter.MarkdownToBBCodeNM from NuGet: $_"
            return $null
        }
    }

    if (-not (Test-Path $toolDll)) {
        Write-Error "Converter.MarkdownToBBCodeNM tool DLL not found at '$toolDll'."
        return $null
    }

    $tempOut = [System.IO.Path]::GetTempFileName()
    try {
        & dotnet $toolDll -i $MarkdownPath -o $tempOut 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempOut)) {
            Write-Error "Failed to convert Markdown to BBCode using Converter.MarkdownToBBCodeNM."
            return $null
        }

        $bbcode = Get-Content -LiteralPath $tempOut -Raw

        # Post-processing: Rewrite relative repository URLs to absolute GitHub URLs if available
        if ($ProjectDir) {
            $webUrl = (Get-ModProjectProperty -ProjectDir $ProjectDir -Property "PackageProjectUrl")
            if (-not $webUrl) {
                $manifestPath = Join-Path $ProjectDir "manifest.json"
                if (Test-Path $manifestPath) {
                    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
                    $webUrl = $m.website_url
                }
            }
            if ($webUrl -and $webUrl -match '^https?://github\.com/[^/]+/[^/]+') {
                $repoUrl = $Matches[0].TrimEnd('/')
                # Fix relative links: [url=filename] -> [url=https://github.com/.../blob/main/filename]
                $bbcode = [regex]::Replace($bbcode, '\[url=([a-zA-Z0-9_\-\./]+(?:\.[a-zA-Z0-9]+))\]', {
                    param($match)
                    $target = $match.Groups[1].Value
                    if ($target -notmatch '^https?://' -and $target -notmatch '^mailto:' -and $target -notmatch '^#') {
                        return "[url=$repoUrl/blob/main/$target]"
                    }
                    return $match.Value
                })
                # Fix relative anchors: [url=README.md#anchor] -> [url=https://github.com/...#anchor]
                $bbcode = [regex]::Replace($bbcode, '\[url=README\.md(#[\w\-]+)\]', {
                    param($match)
                    $anchor = $match.Groups[1].Value
                    return "[url=$repoUrl$anchor]"
                })
            }
        }

        return $bbcode
    } finally {
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
    }
}
