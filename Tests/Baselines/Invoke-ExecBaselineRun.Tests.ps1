BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    function Start-CIPPBaselineOrchestrator { param($TenantFilter, $StandardName, $TemplateId, $Mode, $TriggeredBy, [switch]$Force) }
    function Get-CIPPBaseline { param($ID) }
    function Get-CIPPBaselineOutOfScopeAssignment { param($Assignments) }
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecBaselineRun.ps1')

    function Invoke-Run($Body) {
        Invoke-ExecBaselineRun -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecBaselineRun' }
                Headers = @{}
                Body    = [pscustomobject]$Body
            })
    }
}

Describe 'Invoke-ExecBaselineRun' {
    BeforeEach {
        Mock Start-CIPPBaselineOrchestrator { 3 }
    }

    It 'deploys one standard to all tenants' {
        $Response = Invoke-Run @{ mode = 'oneoff'; tenantFilter = 'AllTenants'; standard = 'DisableGuests' }
        $Response.StatusCode | Should -Be 200
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 1 -ParameterFilter { $null -eq $TenantFilter -and $StandardName -eq 'DisableGuests' -and $Mode -eq 'oneoff' }
    }

    It 'compares one standard across all tenants' {
        $Response = Invoke-Run @{ mode = 'compare'; tenantFilter = 'AllTenants'; standard = 'DisableGuests' }
        $Response.StatusCode | Should -Be 200
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 1 -ParameterFilter { $null -eq $TenantFilter -and $Mode -eq 'compare' }
    }

    It 'accepts the tenant selector option object' {
        $Response = Invoke-Run @{ mode = 'oneoff'; tenantFilter = @{ value = 'contoso.com' }; standard = 'DisableGuests' }
        $Response.StatusCode | Should -Be 200
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' }
    }

    It 'deploys several standards to one tenant in one run' {
        $Response = Invoke-Run @{ mode = 'oneoff'; tenantFilter = 'contoso.com'; standard = @('ConditionalAccessTemplate#a', 'ConditionalAccessTemplate#b') }
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike 'Started the oneoff: 3 checks queued*'
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 1 -ParameterFilter { @($StandardName).Count -eq 2 -and $TenantFilter -eq 'contoso.com' }
    }

    It 'returns 400 with <Expected>' -ForEach @(
        @{ Body = @{ mode = 'bogus'; tenantFilter = 'contoso.com' }; Expected = "Unknown mode 'bogus'*" }
        @{ Body = @{ mode = 'oneoff'; tenantFilter = 'contoso.com' }; Expected = 'A oneoff run deploys a single standard*' }
        @{ Body = @{ mode = 'run'; tenantFilter = 'AllTenants' }; Expected = 'A run across all tenants needs a standard or a templateId*' }
        @{ Body = @{ mode = 'compare'; standard = 'DisableGuests' }; Expected = 'Provide a tenantFilter, a templateId, or a standard*' }
    ) {
        $Response = Invoke-Run $Body
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike $Expected
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 0
    }

    It 'refuses a whole-baseline run when the baseline reaches tenants outside the role' {
        Mock Get-CIPPBaseline { [pscustomobject]@{ assignments = @('fabrikam.com') } }
        Mock Get-CIPPBaselineOutOfScopeAssignment { 'fabrikam.com' }
        $Response = Invoke-Run @{ mode = 'run'; templateId = 'abc' }
        $Response.StatusCode | Should -Be 403
        $Response.Body.Results | Should -BeLike '*outside your access: fabrikam.com*'
        Should -Invoke Start-CIPPBaselineOrchestrator -Times 0
    }

    It 'leaves a tenant-scoped run of a baseline to the dispatcher check' {
        Mock Get-CIPPBaselineOutOfScopeAssignment { 'fabrikam.com' }
        $Response = Invoke-Run @{ mode = 'run'; templateId = 'abc'; tenantFilter = 'contoso.com' }
        $Response.StatusCode | Should -Be 200
        Should -Invoke Get-CIPPBaselineOutOfScopeAssignment -Times 0
    }

    It 'returns the error status when the run fails to start' {
        Mock Start-CIPPBaselineOrchestrator { throw 'table unavailable' }
        $Response = Invoke-Run @{ mode = 'run'; templateId = 'abc' }
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Failed to start baseline run: table unavailable'
    }
}
