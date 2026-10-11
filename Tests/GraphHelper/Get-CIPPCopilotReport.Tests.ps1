BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCopilotReport.ps1')
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream) }
    $Template = "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUserCountSummary(period='{0}')"
}

Describe 'Get-CIPPCopilotReport' {
    It 'asks for D28 by default and passes AsApp and Stream through' {
        Mock New-GraphGetRequest { 'rows' }
        Get-CIPPCopilotReport -UriTemplate $Template -TenantFilter 'contoso.com' -AsApp $true -Stream | Should -Be 'rows'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like "*period='D28')" -and $AsApp -eq $true -and $Stream }
    }

    It 'retries with <Next> when Graph rejects <First>' -ForEach @(
        @{ First = 'D28'; Next = 'D30'; Message = "The period value 'RL28' is not supported with version 'v1'. Use 'RL30' instead." }
        @{ First = 'D30'; Next = 'D28'; Message = "The period value 'RL30' is not supported with version 'v2'. Use 'RL28' instead." }
    ) {
        Mock New-GraphGetRequest { throw $Message } -ParameterFilter { $uri -like "*period='$First')" }
        Mock New-GraphGetRequest { 'second' } -ParameterFilter { $uri -like "*period='$Next')" }
        Get-CIPPCopilotReport -UriTemplate $Template -TenantFilter 'contoso.com' -Period $First | Should -Be 'second'
    }

    It 'rethrows any other error without retrying' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        { Get-CIPPCopilotReport -UriTemplate $Template -TenantFilter 'contoso.com' } | Should -Throw 'Forbidden'
        Should -Invoke New-GraphGetRequest -Times 1
    }
}
