# Pester tests for Invoke-CustomDataSync mapping selection
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CustomDataSync.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-CustomDataSync.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-TenantGroups { param($GroupId) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    # Real group expansion, its own dependencies are stubbed above.
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Expand-CIPPTenantGroups.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)

    . $FunctionPath
}

Describe 'Invoke-CustomDataSync' {
    It 'syncs a mapping scoped to a tenant group that contains the tenant' {
        Mock Get-Tenants { @([pscustomobject]@{ customerId = 'cid-a'; defaultDomainName = 'a.test'; displayName = 'A' }) }
        Mock Get-TenantGroups { [pscustomobject]@{ members = @([pscustomobject]@{ customerId = 'cid-a' }) } }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ JSON = (@{
                        sourceType           = @{ value = 'reportingDb' }
                        directoryObjectType  = @{ value = 'user' }
                        extensionSyncDataset = @{ value = 'Users' }
                        tenantFilter         = @(@{ value = 'group-1'; label = 'Group 1'; type = 'Group' })
                    } | ConvertTo-Json -Depth 5) }
        }
        Mock Get-CippExtensionReportingData { @{} }
        Mock New-GraphBulkRequest { @() }

        Invoke-CustomDataSync -TenantFilter 'a.test' -InformationAction SilentlyContinue 3>$null

        Should -Invoke Get-CippExtensionReportingData -Times 1 -ParameterFilter { $TenantFilter -eq 'a.test' }
    }

    It 'skips a group mapping that does not contain the tenant' {
        Mock Get-Tenants { @([pscustomobject]@{ customerId = 'cid-a'; defaultDomainName = 'a.test'; displayName = 'A' }) }
        Mock Get-TenantGroups { [pscustomobject]@{ members = @([pscustomobject]@{ customerId = 'cid-other' }) } }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ JSON = (@{
                        sourceType           = @{ value = 'reportingDb' }
                        directoryObjectType  = @{ value = 'user' }
                        extensionSyncDataset = @{ value = 'Users' }
                        tenantFilter         = @(@{ value = 'group-1'; label = 'Group 1'; type = 'Group' })
                    } | ConvertTo-Json -Depth 5) }
        }
        Mock Get-CippExtensionReportingData { @{} }

        Invoke-CustomDataSync -TenantFilter 'a.test' -InformationAction SilentlyContinue 3>$null

        Should -Invoke Get-CippExtensionReportingData -Times 0
    }

    It 'syncs a tenant mapping without reading the tenant list' {
        Mock Get-Tenants { }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ JSON = (@{
                        sourceType           = @{ value = 'reportingDb' }
                        directoryObjectType  = @{ value = 'user' }
                        extensionSyncDataset = @{ value = 'Users' }
                        tenantFilter         = @(@{ value = 'a.test'; label = 'A'; type = 'Tenant' })
                    } | ConvertTo-Json -Depth 5) }
        }
        Mock Get-CippExtensionReportingData { @{} }
        Mock New-GraphBulkRequest { @() }

        Invoke-CustomDataSync -TenantFilter 'a.test' -InformationAction SilentlyContinue 3>$null

        Should -Invoke Get-CippExtensionReportingData -Times 1 -ParameterFilter { $TenantFilter -eq 'a.test' }
        Should -Invoke Get-Tenants -Times 0
    }
}
