@{
    RootModule           = 'DW.ValheimModTools.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'b9a67a0e-2d4e-4f18-a621-e37894a8e2cb'
    Author               = 'DreamWraith'
    CompanyName          = 'DreamWraith'
    Copyright            = '(c) 2026 DreamWraith. All rights reserved.'
    Description          = 'Modern PowerShell 7 automation toolkit for packaging, releasing, and publishing game mods (Valheim, BepInEx) to Thunderstore, Hexium, Nexus Mods, and GitHub Releases.'
    PowerShellVersion    = '7.0'
    FunctionsToExport    = @(
        'New-ModPackage',
        'Invoke-ModRelease',
        'Publish-ModPackage',
        'Publish-ThunderstorePackage',
        'Publish-HexiumPackage',
        'Publish-NexusPackage'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags = @('Valheim', 'BepInEx', 'Modding', 'Thunderstore', 'Hexium', 'NexusMods', 'Automation')
            ProjectUri = 'https://github.com/DreamWraith/DW-ValheimModTools'
        }
    }
}

