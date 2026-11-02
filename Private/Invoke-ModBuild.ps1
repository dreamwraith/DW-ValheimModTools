#requires -Version 7

function Invoke-ModBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectDir,

        [string]$Configuration = "Release"
    )

    # Packaging runs as its own step, so the Release build must not also zip
    dotnet build (Join-Path $ProjectDir "") -c $Configuration -p:SkipPackageMod=true | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed with exit code $LASTEXITCODE."
        exit $LASTEXITCODE
    }
}
