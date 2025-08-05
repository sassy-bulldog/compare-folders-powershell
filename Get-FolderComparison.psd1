@{
    # Module manifest for Get-FolderComparison
    RootModule = 'Get-FolderComparison.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'David White'
    CompanyName = 'sassy-bulldog'
    Copyright = '(c) 2025 David White. All rights reserved.'
    Description = 'Compares two folders and reports file changes, moves, renames, and updates using MD5 checksums and similarity detection.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'
    
    # Functions to export from this module
    FunctionsToExport = @('Get-FolderComparison')
    
    # Cmdlets to export from this module
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module
            Tags = @('FolderComparison', 'FileSync', 'MD5', 'PowerShell')
            
            # A URL to the license for this module
            LicenseUri = 'https://github.com/sassy-bulldog/compare-folders-powershell/blob/main/LICENSE.txt'
            
            # A URL to the main website for this project
            ProjectUri = 'https://github.com/sassy-bulldog/compare-folders-powershell'
            
            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release of Get-FolderComparison module'
        }
    }
}
