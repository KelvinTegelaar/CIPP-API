BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Set-CIPPGSAFilteringPolicy { param($TenantFilter, $Policy, $Current) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ExecDeployGSAFilteringPolicyTemplate.ps1').FullName

    function Invoke-Deploy([string[]]$Tenants, [string]$TemplateId = 'pol-1') {
        Invoke-ExecDeployGSAFilteringPolicyTemplate -Request ([pscustomobject]@{
                Params = @{ CIPPEndpoint = 'ExecDeployGSAFilteringPolicyTemplate' }
                Body   = [pscustomobject]@{ TemplateList = @{ value = $TemplateId }; tenantFilter = @($Tenants.ForEach({ @{ value = $_; label = $_ } })) }
            })
    }
}

Describe 'Invoke-ExecDeployGSAFilteringPolicyTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'pol-1'; JSON = '{"name":"Block risky","action":"block","policyRules":[]}' } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $TenantFilter -ne 'nolicence.com' } }
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'tenant-pol'; name = 'Block risky' }) } -ParameterFilter { $tenantid -eq 'has.com' }
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'x'; name = 'Something else' }) } -ParameterFilter { $tenantid -ne 'has.com' }
        Mock Set-CIPPGSAFilteringPolicy { 'id' }
    }

    It 'requires a template and at least one tenant' {
        (Invoke-ExecDeployGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Body = [pscustomobject]@{ tenantFilter = @() } })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns 404 for a template that does not exist' {
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        (Invoke-Deploy 'new.com').StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'creates the policy where the tenant has none by that name and updates it where it does' {
        $Response = Invoke-Deploy 'new.com', 'has.com'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results.resultText) | Should -Be @("new.com: Created filtering policy 'Block risky'", "has.com: Updated filtering policy 'Block risky'")
        Should -Invoke Set-CIPPGSAFilteringPolicy -Times 1 -ParameterFilter { $TenantFilter -eq 'new.com' -and $null -eq $Current }
        Should -Invoke Set-CIPPGSAFilteringPolicy -Times 1 -ParameterFilter { $TenantFilter -eq 'has.com' -and $Current.id -eq 'tenant-pol' }
    }

    It 'skips a tenant without Internet Access and reports 207 when another tenant worked' {
        $Response = Invoke-Deploy 'nolicence.com', 'new.com'
        $Response.StatusCode | Should -Be 207
        $Response.Body.Results[0].resultText | Should -BeLike 'nolicence.com: web content filtering needs*'
        Should -Invoke Set-CIPPGSAFilteringPolicy -Times 0 -ParameterFilter { $TenantFilter -eq 'nolicence.com' }
    }
}
