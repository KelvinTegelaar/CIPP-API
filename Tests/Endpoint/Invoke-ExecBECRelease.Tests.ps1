# Pester tests for Invoke-ExecBECRelease: required fields, the typed-UPN confirmation and the pass-through
# of the selected actions.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, [switch]$IncludeResults) }
    function Invoke-CIPPBecRelease { param($TenantFilter, $CaseId, $Actions, $Headers, $APIName) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECRelease.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECRelease' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = 'x' }
            Query   = $null
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecBECRelease' {
    BeforeEach {
        Mock Get-CIPPBecReport { [pscustomobject]@{ UserPrincipalName = 'victim@contoso.com' } }
        Mock Invoke-CIPPBecRelease { @([pscustomobject]@{ Action = 'DisableAccount'; Target = 'victim@contoso.com'; state = 'success'; resultText = 'ok' }) }
        Mock Write-LogMessage { }
    }

    It 'releases the selected actions once the UPN is typed' {
        $Response = Invoke-ExecBECRelease -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Actions = @('DisableAccount'); Confirmation = ' Victim@Contoso.com ' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0].state | Should -Be 'success'
        Should -Invoke Invoke-CIPPBecRelease -Times 1 -Exactly -ParameterFilter { $CaseId -eq 'BEC-1' -and (@($Actions) -join ',') -eq 'DisableAccount' }
    }

    It 'returns 400 and releases nothing without the typed UPN' {
        $Response = Invoke-ExecBECRelease -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Confirmation = 'someone@contoso.com' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-CIPPBecRelease -Times 0 -Exactly
    }

    It 'returns 404 for an unknown case' {
        Mock Get-CIPPBecReport { }

        $Response = Invoke-ExecBECRelease -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-9'; Confirmation = 'victim@contoso.com' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 404
        Should -Invoke Invoke-CIPPBecRelease -Times 0 -Exactly
    }

    It 'returns 400 without a tenant or case' {
        $Response = Invoke-ExecBECRelease -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        Should -Invoke Get-CIPPBecReport -Times 0 -Exactly
    }
}
