@{
    # The module version should be SemVer.org compatible
    ModuleVersion          = '3.1.8'

    # PrivateData is where all third-party metadata goes
    PrivateData            = @{
        # PrivateData.PSData is the PowerShell Gallery data
        PSData             = @{
            # Prerelease string should be here, so we can set it
            Prerelease     = ''

            # Release Notes have to be here, so we can update them
            ReleaseNotes   = '
            ModuleBuilder v3.1.8+Build.local.Branch.main.Sha.b4d5aaf9df98194aa7d40c46cd3d7ca787011c54.Date.20250412T215606
            Fix case sensitivity of defaults for SourceDirectories and PublicFilter
            '

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags           = 'Authoring','Build','Development','BestPractices'

            # A URL to the license for this module.
            LicenseUri     = 'https://github.com/PoshCode/ModuleBuilder/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri     = 'https://github.com/PoshCode/ModuleBuilder'

            # A URL to an icon representing this module.
            IconUri        = 'https://github.com/PoshCode/ModuleBuilder/blob/resources/ModuleBuilder.png?raw=true'
        } # End of PSData
    } # End of PrivateData

    # The main script module that is automatically loaded as part of this module
    RootModule             = 'ModuleBuilder.psm1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules        = @('Configuration')

    # Always define FunctionsToExport as an empty @() which will be replaced on build
    FunctionsToExport      = @('Build-Module','Convert-Breakpoint','Convert-CodeCoverage','ConvertFrom-SourceLineNumber','ConvertTo-SourceLineNumber')
    AliasesToExport        = @('build','Convert-LineNumber')

    # ID used to uniquely identify this module
    GUID                   = '4775ad56-8f64-432f-8da7-87ddf7a34653'
    Description            = 'A module for authoring and building PowerShell modules'

    # Common stuff for all our modules:
    CompanyName            = 'PoshCode'
    Author                 = 'Joel Bennett'
    Copyright              = "Copyright 2018 Joel Bennett"

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion      = '5.1'
    CompatiblePSEditions = @('Core','Desktop')
}
