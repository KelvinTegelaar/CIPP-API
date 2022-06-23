@{

# ID used to uniquely identify this module
GUID = '0ed51f07-bcc5-429d-9322-0477168a0926'

# Author of this module
Author = 'Paulo Marques (MSFT)'

# Company or vendor of this module
CompanyName = 'Microsoft Corporation'

# Copyright statement for this module
Copyright = '© Microsoft Corporation. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Sample functions to add/retrieve/update entities on Azure Storage Tables from PowerShell (This is the same as AzureRmStorageTable module but with a new module name). It requires latest PowerShell Az module installed. Instructions at https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-1.6.0. For documentation, please visit https://paulomarquesc.github.io/working-with-azure-storage-tables-from-powershell/.'

# HelpInfo URI of this module
HelpInfoUri = 'https://github.com/paulomarquesc/AzureRmStorageTable/tree/master/docs'

# Version number of this module
ModuleVersion = '2.1.0'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '4.0'

# Minimum version of the common language runtime (CLR) required by this module
CLRVersion = '2.0'

# Script module or binary module file associated with this manifest
#ModuleToProcess = ''

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @('AzureRmStorageTableCoreHelper.psm1')

FunctionsToExport = @(  'Add-AzTableRow',
                        'Get-AzTableRow',
                        'Get-AzTableRowAll',
                        'Get-AzTableRowByPartitionKeyRowKey',
                        'Get-AzTableRowByPartitionKey',
                        'Get-AzTableRowByColumnName',
                        'Get-AzTableRowByCustomFilter',
                        'Update-AzTableRow',
                        'Remove-AzTableRow',
                        'Get-AzTableTable'
                        )

VariablesToExport = ''

AliasesToExport = '*'

}
