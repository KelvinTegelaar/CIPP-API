@{
    # Script module or binary module file associated with this manifest.
    RootModule = '.\CIPPStandardsAlerts.psm1'

    # Version number of this module.
    ModuleVersion = '1.0'

    # ID used to uniquely identify this module
    GUID = 'e5f12345-6789-abcd-ef01-234567890abc'

    # Author of this module
    Author = 'Kelvin Tegelaar - Kelvin@cyberdrain.com'

    # Company or vendor of this module
    CompanyName = 'CyberDrain.com'

    # Copyright statement for this module
    Copyright = '(c) 2020 Kelvin Tegelaar - Kelvin@CyberDrain.com All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'CIPP Standards & Alerts Functions'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = '*'

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('CIPP', 'Standards', 'M365', 'Automation')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/KelvinTegelaar/CIPP-API/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/KelvinTegelaar/CIPP-API'

            # ReleaseNotes of this module
            ReleaseNotes = 'CIPP Standards and Alerts Functions separated from CIPPCore for performance optimization'

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    HelpInfoURI = 'https://github.com/KelvinTegelaar/CIPP-API'

}
