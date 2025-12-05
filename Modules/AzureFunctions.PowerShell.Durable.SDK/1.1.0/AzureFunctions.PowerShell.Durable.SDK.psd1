@{    
    # Version number of this module.
    ModuleVersion = '1.1.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')
    
    # ID used to uniquely identify this module
    GUID = '841fad61-94f5-4330-89be-613d54165289'
    
    # Author of this module
    Author = 'Microsoft Corporation'
    
    # Company or vendor of this module
    CompanyName = 'Microsoft Corporation'
    
    # Copyright statement for this module
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'Initial release of the Durable Functions SDK for PowerShell. This package is to be used exclusively with the Azure Functions PowerShell worker.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.2'
    
    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @() # TODO: use this for pretty-printing DF tasks
    
    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @() # TODO: use this for pretty-printing DF tasks
    
    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules = @('./AzureFunctions.PowerShell.Durable.SDK.dll', './AzureFunctions.PowerShell.Durable.SDK.psm1')
    
    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Get-DurableStatus',
        'New-DurableOrchestrationCheckStatusResponse',
        'Send-DurableExternalEvent',
        'Start-DurableOrchestration',
        'Stop-DurableOrchestration',
        'Suspend-DurableOrchestration',
        'Resume-DurableOrchestration'
    )
    
    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @(
       'Invoke-DurableActivity',
       'Invoke-DurableSubOrchestrator',
       'New-DurableRetryPolicy',
       'Set-DurableCustomStatus',
       'Set-FunctionInvocationContext',
       'Start-DurableExternalEventListener'
       'Start-DurableTimer',
       'Stop-DurableTimerTask',
       'Wait-DurableTask',
       'Get-DurableTaskResult'
    )
    
    # Variables to export from this module
    VariablesToExport = '*'
    
    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @(
        'Invoke-ActivityFunction',
        'New-OrchestrationCheckStatusResponse',
        'Start-NewOrchestration',
        'Wait-ActivityFunction',
        'New-DurableRetryOptions'
    )
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
    
        PSData = @{
    
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Microsoft', 'Azure', 'Functions', 'Serverless', 'Cloud', 'Workflows', 'Durable', 'DurableTask')
    
            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Azure/azure-functions-durable-powershell/blob/main/LICENSE'
    
            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Azure/azure-functions-durable-powershell'
    
            # ReleaseNotes of this module
            # ReleaseNotes = '' #TODO: add release notes.
    
            # Prerelease string of this module
            #Prerelease = 'alpha'
    
        } # End of PSData hashtable
    } # End of PrivateData hashtable   

    # HelpInfo URI of this module
    # HelpInfoURI = '' # TODO: explore
}