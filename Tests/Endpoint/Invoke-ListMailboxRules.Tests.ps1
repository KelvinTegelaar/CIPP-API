# Pester tests for Invoke-ListMailboxRules: every read comes from the reporting database, paged only
# when manualPagination is set, as on the other report-backed list endpoints.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPMailboxRulesReport { param($TenantFilter) }
    function Get-CIPPReportPage { param($TenantFilter, $Type, $Report, $PageSize, $ContinuationToken) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Administration/Invoke-ListMailboxRules.ps1')

    function Invoke-List ($Query) { Invoke-ListMailboxRules -Request ([pscustomobject]@{ Query = [pscustomobject]$Query }) -TriggerMetadata $null }
}

Describe 'Invoke-ListMailboxRules' {
    BeforeEach {
        Mock Get-CIPPReportPage {
            param($TenantFilter, $Type, $Report, $PageSize, $ContinuationToken)
            [pscustomobject]@{ Results = @(& $Report 'a.com'); Metadata = @{ nextLink = 'a.com' } }
        }
        Mock Get-CIPPMailboxRulesReport { [pscustomobject]@{ Name = 'Forward all'; Tenant = 'a.com' } }
    }

    It 'pages an AllTenants read when manualPagination is set' {
        $Response = Invoke-List @{ tenantFilter = 'AllTenants'; manualPagination = 'true' }

        Should -Invoke Get-CIPPReportPage -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'AllTenants' -and $Type -eq 'MailboxRules' }
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Name | Should -Be 'Forward all'
        $Response.Body.Metadata.nextLink | Should -Be 'a.com'
    }

    It 'returns the whole report as an array without manualPagination' {
        $Response = Invoke-List @{ tenantFilter = 'AllTenants' }

        Should -Invoke Get-CIPPReportPage -Times 0
        @($Response.Body).Name | Should -Be 'Forward all'
    }

    It 'returns 404 when a tenant has no cached rules' {
        Mock Get-CIPPMailboxRulesReport { throw [System.Management.Automation.ItemNotFoundException]::new('No mailbox rules data found in reporting database. Sync the report data first.') }

        $Response = Invoke-List @{ tenantFilter = 'b.com' }

        $Response.StatusCode | Should -Be 404
        @($Response.Body) | Should -Match 'Sync the report data first'
    }
}
