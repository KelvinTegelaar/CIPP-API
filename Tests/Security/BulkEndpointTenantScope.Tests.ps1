# Bulk "Add/Deploy" endpoints take their targets from selectedTenants in the body. A tenant-scoped role must
# not be able to reach tenants outside its scope that way, so each handler must narrow selectedTenants to the
# caller's allowed tenants (Test-CippAccess -TenantList). One handler is exercised behaviourally; the rest are
# guarded by source so the filter cannot be dropped and new bulk endpoints are caught in review.

$script:ScopedHandlers = @(
    'Email-Exchange/Transport/Invoke-AddConnectionFilter.ps1'
    'Security/Compliance-SIT/Invoke-AddSensitiveInfoType.ps1'
    'Endpoint/Autopilot/Invoke-AddEnrollment.ps1'
    'Endpoint/Autopilot/Invoke-AddAutopilotConfig.ps1'
    'Security/Compliance-SensitivityLabel/Invoke-AddSensitivityLabel.ps1'
    'Security/Compliance-Retention/Invoke-AddRetentionCompliancePolicy.ps1'
    'Security/Compliance-DLP/Invoke-AddDlpCompliancePolicy.ps1'
    'Endpoint/MEM/Invoke-AddDefenderDeployment.ps1'
    'Email-Exchange/Spamfilter/Invoke-AddQuarantinePolicy.ps1'
    'Security/Safe-Links-Policy/Invoke-AddSafeLinksPolicyFromTemplate.ps1'
    'Email-Exchange/Administration/Contacts/Invoke-DeployContactTemplates.ps1'
)

Describe 'Bulk endpoint tenant-scope source guard' {
    It 'narrows selectedTenants to the caller scope: <_>' -ForEach $script:ScopedHandlers {
        $Root = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
        $Path = Join-Path $Root $_
        (Get-Content $Path -Raw) | Should -Match 'Test-CippAccess -Request \$Request -TenantList' `
            -Because "$_ exposes selectedTenants and must filter it against the caller's allowed tenants"
    }
}

Describe 'Invoke-AddConnectionFilter tenant-scope enforcement' {
    BeforeAll {
        $EntrypointRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
        $FunctionPath = Join-Path $EntrypointRoot 'Email-Exchange/Transport/Invoke-AddConnectionFilter.ps1'
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
        class HttpResponseContext { [int]$StatusCode; [object]$Body }
        function Test-CippAccess { param($Request, [switch]$TenantList) }
        function Get-Tenants { param([switch]$IncludeErrors) }
        function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
        function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
        function Get-CippException { param($Exception) @{} }
        function Get-CippBulkStatusCode { param($Total, $Failed) [System.Net.HttpStatusCode]::OK }
        . $FunctionPath

        $script:TwoTenants = @(
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000000'; defaultDomainName = 'a.onmicrosoft.com' }
            [pscustomobject]@{ customerId = 'bbbbbbbb-0000-0000-0000-000000000000'; defaultDomainName = 'b.onmicrosoft.com' }
        )
        $script:Req = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'AddConnectionFilter' }
            Headers = @{}
            Body   = [pscustomobject]@{
                PowerShellCommand = '{"name":"cf"}'
                selectedTenants   = @([pscustomobject]@{ value = 'a.onmicrosoft.com' }, [pscustomobject]@{ value = 'b.onmicrosoft.com' })
            }
        }
    }

    BeforeEach {
        Mock Get-Tenants { $script:TwoTenants }
        Mock New-ExoRequest { }
    }

    It 'processes only the tenant the scoped role is allowed, dropping the out-of-scope one' {
        Mock Test-CippAccess { @('aaaaaaaa-0000-0000-0000-000000000000') }
        $null = Invoke-AddConnectionFilter -Request $script:Req
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'a.onmicrosoft.com' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $tenantid -eq 'b.onmicrosoft.com' }
    }

    It 'processes every selected tenant when the caller is unrestricted' {
        Mock Test-CippAccess { 'AllTenants' }
        $null = Invoke-AddConnectionFilter -Request $script:Req
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'a.onmicrosoft.com' }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'b.onmicrosoft.com' }
    }
}
