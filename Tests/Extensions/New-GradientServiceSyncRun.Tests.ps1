# Pester tests for New-GradientServiceSyncRun.
#
# Licence counts are read from the reporting DB (LicenseOverview) instead of a live subscribedSkus
# call per tenant. The old path ran those calls in a parallel runspace; when they failed it posted a
# placeholder whose prepaidUnits was a scriptblock, so Gradient received unitCount null and rejected
# every client ("unitCount must be a number"), and created a "Could not connect to client" service.

BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Gradient/New-GradientServiceSyncRun.ps1"

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-GradientToken { param($Configuration) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($API, $message, $Sev, $tenant) }

    $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
}

Describe 'New-GradientServiceSyncRun licence sync' {
    BeforeEach {
        $script:CountPosts = [System.Collections.Generic.List[object]]::new()
        $script:Sessions = [System.Collections.Generic.List[object]]::new()

        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ config = '{"Gradient":{}}' } }
        Mock Get-GradientToken { @{ Authorization = 'x' } }
        Mock Write-LogMessage { }
        Mock New-GraphGetRequest { throw 'no live Graph calls expected' }
        Mock Get-Tenants {
            @(
                [pscustomobject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com' }
                [pscustomobject]@{ displayName = 'Fabrikam'; defaultDomainName = 'fabrikam.onmicrosoft.com' }
            )
        }
        Mock New-CIPPDbRequest {
            if ($TenantFilter -eq 'contoso.onmicrosoft.com') {
                [pscustomobject]@{ skuId = '05e9a617-0261-4cee-bb44-138d3ef5d965'; License = 'Microsoft 365 E3'; TotalLicenses = '25' }
            }
        }
        Mock Invoke-RestMethod {
            $script:Sessions.Add($WebSession)
            if ($Uri -like '*/organization/accounts') { return @() }
            if ($Uri -like '*/vendor-api/organization') { return [pscustomobject]@{ Status = 'active' } }
            if ($Uri -like '*/vendor-api') { return [pscustomobject]@{ data = [pscustomobject]@{ skus = @([pscustomobject]@{ name = 'Microsoft 365 E3'; id = 'svc-1' }) } } }
            if ($Uri -like '*/count') { $script:CountPosts.Add(($Body | ConvertFrom-Json)); return $null }
        }
    }

    It 'posts the cached purchased count as a number, without calling Graph' {
        New-GradientServiceSyncRun

        $script:CountPosts.Count | Should -Be 1
        $script:CountPosts[0].accountId | Should -Be 'contoso.onmicrosoft.com'
        $script:CountPosts[0].unitCount | Should -Be 25
        $script:CountPosts[0].unitCount | Should -BeOfType [long]
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke New-CIPPDbRequest -ParameterFilter { $Type -eq 'LicenseOverview' } -Times 2 -Exactly
    }

    It 'sends every Gradient call on one shared web session' {
        New-GradientServiceSyncRun

        $script:Sessions.Count | Should -BeGreaterThan 3
        @($script:Sessions | Where-Object { $null -eq $_ }).Count | Should -Be 0
        $script:Sessions[0] | Should -BeOfType [Microsoft.PowerShell.Commands.WebRequestSession]
        @($script:Sessions | Where-Object { -not [object]::ReferenceEquals($_, $script:Sessions[0]) }).Count | Should -Be 0
    }

    It 'reads the service catalogue once per run, not once per licence' {
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ skuId = '05e9a617-0261-4cee-bb44-138d3ef5d965'; License = 'Microsoft 365 E3'; TotalLicenses = '25' }
            [pscustomobject]@{ skuId = '00000000-0000-0000-0000-00000000c0de'; License = 'Microsoft 365 E3'; TotalLicenses = '3' }
        }

        New-GradientServiceSyncRun

        $script:CountPosts.Count | Should -Be 4
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api' } -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api/service' } -Times 0 -Exactly
    }

    It 'creates a missing service once and reuses it for later tenants' {
        Mock New-CIPPDbRequest { [pscustomobject]@{ skuId = '00000000-0000-0000-0000-00000000c0de'; License = 'Custom Licence'; TotalLicenses = '7' } }
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api/service' } {
            [pscustomobject]@{ skus = @([pscustomobject]@{ name = 'Custom Licence'; id = 'svc-new' }) }
        }

        New-GradientServiceSyncRun

        Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api/service' } -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -like '*/service/svc-new/count' } -Times 2 -Exactly
        @($script:CountPosts.accountId) | Should -Be @('contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com')
    }

    It 'skips the licence sync instead of creating services when the catalogue cannot be read' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api' } { throw 'catalogue unavailable' }

        New-GradientServiceSyncRun

        Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -like '*/vendor-api/service' } -Times 0 -Exactly
        $script:CountPosts.Count | Should -Be 0
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like 'Failed to read the Gradient service catalogue*' } -Times 1 -Exactly
    }

    It 'skips a tenant with no cached licence data and says so' {
        New-GradientServiceSyncRun

        @($script:CountPosts | Where-Object accountId -EQ 'fabrikam.onmicrosoft.com').Count | Should -Be 0
        Should -Invoke Write-LogMessage -ParameterFilter { $tenant -eq 'fabrikam.onmicrosoft.com' -and $message -like 'No cached licence data*' } -Times 1 -Exactly
    }
}
