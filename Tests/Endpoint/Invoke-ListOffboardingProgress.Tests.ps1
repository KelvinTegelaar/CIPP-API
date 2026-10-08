# Live progress pushes every row of a job to whoever is granted it, so reading the job only grants it to a
# caller allowed to see all of its rows; a tenant-restricted caller keeps polling its filtered view.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline = $true)]$InputObject, $TenantProperty) process { $InputObject } }
    function Add-CIPPRealtimeWatch { param($JobId, [switch]$Run) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListOffboardingProgress.ps1' | Select-Object -First 1).FullName

    $script:Job = '6f1c2b8e-1d2a-4c1e-9f0a-3b2c1d4e5f60'
    $script:Request = [pscustomobject]@{ Query = [pscustomobject]@{ DeploymentId = $script:Job } }
    $script:Rows = @(
        [pscustomobject]@{ Name = 'pat@contoso.com'; TenantFilter = 'contoso.com'; Status = 'running' }
        [pscustomobject]@{ Name = 'sam@fabrikam.com'; TenantFilter = 'fabrikam.com'; Status = 'running' }
    )
}

Describe 'Invoke-ListOffboardingProgress live grant' {
    BeforeEach {
        Mock Get-CIPPAsyncDeployment { $script:Rows }
        Mock Add-CIPPRealtimeWatch { }
    }

    It 'grants the job to a caller who may read every row' {
        Mock Select-CippAllowedTenantData { process { $InputObject } }

        $null = Invoke-ListOffboardingProgress -Request $script:Request

        Should -Invoke Add-CIPPRealtimeWatch -Times 1 -Exactly -ParameterFilter { $JobId -eq $script:Job -and -not $Run }
    }

    It 'does not grant it when the caller''s tenant scope hides a row' {
        Mock Select-CippAllowedTenantData { process { if ($InputObject.TenantFilter -eq 'contoso.com') { $InputObject } } }

        $Response = Invoke-ListOffboardingProgress -Request $script:Request

        Should -Invoke Add-CIPPRealtimeWatch -Times 0 -Exactly
        @($Response.Body | ConvertFrom-Json).Name | Should -Be @('pat@contoso.com')
    }
}
