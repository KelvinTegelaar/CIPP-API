# Pester tests for Invoke-ExecIncidentsList reading AllTenants through the graph request cache

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $IncidentsPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Incidents'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Get-GraphRequestList { param($TenantFilter, $Endpoint, $Parameters, $AsApp, $CacheStatus) }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $IncidentsPath 'Invoke-ExecIncidentsList.ps1')
}

Describe 'Invoke-ExecIncidentsList for AllTenants' {
    BeforeAll {
        Mock Get-GraphRequestList {
            [pscustomobject]@{ id = '1'; displayName = 'Old'; createdDateTime = '2026-09-01T10:00:00Z'; Tenant = 'a.com' }
            [pscustomobject]@{ id = '2'; displayName = 'In range'; createdDateTime = '2026-10-02T10:00:00Z'; Tenant = 'b.com' }
            [pscustomobject]@{ Tenant = 'c.com'; CippStatus = 'Could not connect to tenant.' }
        }
    }

    It 'reads incidents as the app and keeps only those in the date range' {
        $request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'AllTenants'; StartDate = '20261001'; EndDate = '20261002' } }

        $response = Invoke-ExecIncidentsList -Request $request -TriggerMetadata $null

        Should -Invoke Get-GraphRequestList -Times 1 -Exactly -ParameterFilter { $Endpoint -eq 'security/incidents' -and $AsApp -eq $true }
        $response.StatusCode | Should -Be 200
        @($response.Body.Results).ForEach({ "$($_.Tenant)/$($_.DisplayName)" }) | Should -Be 'b.com/In range'
    }
}
