BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Domain Analyser/Push-DomainAnalyserTenant.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPDomainExclusionList.ps1')

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
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'contoso.com' }
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

    It 'removes every row when the tenant has no analysable domains left' {
        Mock New-CIPPDbRequest {
            @([pscustomobject]@{ id = 'contoso.com'; isVerified = $false })
        }

        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        @($script:Removed.RowKey) | Should -Be @('contoso.com', 'contoso.onmicrosoft.com', 'old-contoso.com')
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'removes a row whose key differs from the domain only in case' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*TenantGUID*') {
                @(
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'Contoso.com' }
                    [pscustomobject]@{ PartitionKey = 'TenantDomains'; RowKey = 'contoso.onmicrosoft.com' }
                )
            }
        }

        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        @($script:Removed.RowKey) | Should -Be @('Contoso.com')
    }

    It 'keeps every row when the cached domain data is empty' {
        Mock New-CIPPDbRequest { }

        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'drops domains matching the global exclusion list' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*RowKey eq 'Domains'*") { [pscustomobject]@{ DomainExclusions = '["*.voice.example.com"]' } }
        }
        Mock New-CIPPDbRequest {
            @(
                [pscustomobject]@{ id = 'contoso.com'; isVerified = $true }
                [pscustomobject]@{ id = 'contoso.voice.example.com'; isVerified = $true }
            )
        }
        Mock Add-CIPPAzDataTableEntity { $script:Added = $Entity }

        Push-DomainAnalyserTenant -Item @{ customerId = 'g1' }

        @($script:Added.RowKey) | Should -Be @('contoso.com')
    }
}
