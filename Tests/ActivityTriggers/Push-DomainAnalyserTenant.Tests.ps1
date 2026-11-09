BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Domain Analyser/Push-DomainAnalyserTenant.ps1')

    function Get-Tenants { param($TenantFilter, [switch]$IncludeAll) }
    function Get-CippTable { param($tablename) @{ Name = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Name, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Name, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Name, $Entity, [switch]$Force) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $tenantid, $message, $LogData, $sev) }
    function Get-CippException { param($Exception) }
}

Describe 'Push-DomainAnalyserTenant' {
    BeforeEach {
        $script:Removed = $null
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'g1'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com'; Excluded = $false } }
        Mock New-CIPPDbRequest {
            @(
                [pscustomobject]@{ id = 'contoso.com'; isVerified = $true }
                [pscustomobject]@{ id = 'contoso.onmicrosoft.com'; isVerified = $true }
            )
        }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*TenantGUID*') {
                @(
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'Contoso.com' }
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'contoso.onmicrosoft.com' }
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'old-contoso.com' }
                )
            }
        }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed = $Entity }
        Mock Start-CIPPOrchestrator { }
        Mock Write-LogMessage { }
    }

    It 'removes only the rows for domains the tenant no longer has' {
        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        @($script:Removed.RowKey) | Should -Be @('old-contoso.com')
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 'TenantDomains' and TenantGUID eq 'g1'" }
    }

    It 'removes nothing when every row is still a tenant domain' {
        Mock New-CIPPDbRequest {
            @(
                [pscustomobject]@{ id = 'contoso.com'; isVerified = $true }
                [pscustomobject]@{ id = 'contoso.onmicrosoft.com'; isVerified = $true }
                [pscustomobject]@{ id = 'old-contoso.com'; isVerified = $true }
            )
        }

        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
