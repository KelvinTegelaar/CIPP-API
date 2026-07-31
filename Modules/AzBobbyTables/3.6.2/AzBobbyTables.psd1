@{

# Script module or binary module file associated with this manifest.
RootModule = 'AzBobbyTables.PS.dll'

# Version number of this module.
ModuleVersion = '3.6.2'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = 'eead4f42-5080-4f83-8901-340c529a5a11'

# Author of this module
Author = 'Emanuel Palm'

# Company or vendor of this module
CompanyName = 'pipe.how'

# Copyright statement for this module
Copyright = '(c) Emanuel Palm. All rights reserved.'

# Description of the functionality provided by this module
Description = 'A module for handling Azure Table Storage operations by wrapping the Azure Data Tables SDK.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.0'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @()

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @(
    'Add-AzDataTableEntity'
    'Add-AzDataTableLargeEntity'
    'Clear-AzDataTable'
    'Get-AzDataTable'
    'Get-AzDataTableEntity'
    'Get-AzDataTableLargeEntity'
    'Get-AzDataTableSupportedEntityType'
    'Remove-AzDataTableEntity'
    'Remove-AzDataTableLargeEntity'
    'Update-AzDataTableEntity'
    'New-AzDataTableContext'
    'Remove-AzDataTable'
    'New-AzDataTable'
)

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('azure', 'storage', 'table', 'cosmos', 'cosmosdb', 'data')

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/PalmEmanuel/AzBobbyTables/blob/main/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/PalmEmanuel/AzBobbyTables'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
          ReleaseNotes = '## [3.6.2] - 2026-08-01

### Added

- Added `Add-AzDataTableLargeEntity`, `Get-AzDataTableLargeEntity` and `Remove-AzDataTableLargeEntity` for working with entities that exceed the Azure Table Storage size limits (64 KiB per string property, 1 MiB per entity). Oversized string properties are split into chunk properties recorded in a `SplitOverProps` JSON manifest, and entities that are still too large are distributed over multiple rows marked with `OriginalEntityId` and `PartIndex`; reads reassemble the original entity transparently and removes delete all part rows. The existing entity cmdlets are unaffected.

### Fixed

- `Get-AzDataTableEntity` no longer fails with `400 InvalidInput` when `-First` is given a value above 1000. The page-size hint introduced in 3.6.1 was passed to the service unclamped, and Azure Table Storage rejects a page size over its limit of 1000 rather than capping it. The hint is now clamped to that limit. Results are unchanged: the hint only sizes each page, so requests for more than 1000 entities are served by paging, as they were before 3.6.1.

'

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        # ExternalModuleDependencies = @()

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}
