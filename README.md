# DW.ValheimModTools

Modern PowerShell 7 automation toolkit for packaging, releasing, and publishing game mods (Valheim, BepInEx) to **Thunderstore**, **Hexium**, **Nexus Mods**, and **GitHub Releases**.

> [!WARNING]
> This code is not yet cleaned up or optimized. It was hacked together in a very slapdash way and should be considered firmly in alpha territory.
> It is likely full of mistakes, rough edges, and assumptions that may change without notice. This is a very early, experimental project and should be used with caution.

---

## Exported Cmdlets

| Cmdlet | Description |
| :--- | :--- |
| `New-ModPackage` | Bumps version, syncs `manifest.json`, stages artifacts, builds release & source archives, extracts changelog. |
| `Invoke-ModRelease` | Builds project, creates distribution archive, syncs GitHub secrets via `gh`, and creates draft/published GitHub Releases. |
| `Publish-ModPackage` | Master publisher orchestrator targeting `All`, `Thunderstore`, `Hexium`, or `Nexus`. |
| `Publish-ThunderstorePackage` | Direct Thunderstore API submitter. |
| `Publish-HexiumPackage` | Direct Hexium API submitter. |
| `Publish-NexusPackage` | Direct Nexus Mods v3 S3 multipart upload and file version creator. |

---

## Local Usage

Import directly from your local repository or clone into your PowerShell modules path (`$HOME\Documents\PowerShell\Modules\DW.ValheimModTools`):

```powershell
Import-Module C:\Users\slugw\source\DW-ValheimModTools\DW.ValheimModTools.psd1 -Force
```

Run in any mod project directory:

```powershell
# Create release archive
New-ModPackage

# Create GitHub Release with version bump
Invoke-ModRelease -Bump Patch

# Publish to portals
Publish-ModPackage -Target All -DryRun
```

---

## License

This project is provided as-is, without warranty or guarantee of fitness for any particular purpose. See the full license details in [LICENSE.md](./LICENSE.md).

