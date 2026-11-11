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
    function Sync-CIPPGSAFilteringProfile { param($ProfileTemplate, $PolicyTemplates, $TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ExecDeployGSASecurityProfileTemplate.ps1').FullName

    function Invoke-Deploy([string[]]$Tenants, [string]$TemplateId = 'prof-1') {
        Invoke-ExecDeployGSASecurityProfileTemplate -Request ([pscustomobject]@{
                Params = @{ CIPPEndpoint = 'ExecDeployGSASecurityProfileTemplate' }
                Body   = [pscustomobject]@{ TemplateList = @{ value = $TemplateId }; tenantFilter = @($Tenants.ForEach({ @{ value = $_; label = $_ } })) }
            })
    }
}

Describe 'Invoke-ExecDeployGSASecurityProfileTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'prof-1'; JSON = '{"name":"Staff","priority":1000,"policies":[]}' } } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'pol-1'; JSON = '{"name":"Block risky"}' } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $TenantFilter -ne 'nolicence.com' } }
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = 'p'; Results = @([pscustomobject]@{ state = 'success'; resultText = "Created security profile 'Staff'" }) } }
    }

    It 'requires a template and at least one tenant' {
        (Invoke-ExecDeployGSASecurityProfileTemplate -Request ([pscustomobject]@{ Body = [pscustomobject]@{ tenantFilter = @() } })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns 404 for a template that does not exist' {
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        (Invoke-Deploy 'contoso.com').StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0
    }

    It 'deploys with the template and its policy templates, prefixing each result with the tenant' {
        $Response = Invoke-Deploy 'contoso.com'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results[0].resultText | Should -Be "contoso.com: Created security profile 'Staff'"
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $ProfileTemplate.name -eq 'Staff' -and $PolicyTemplates['pol-1'].name -eq 'Block risky' }
    }

    It 'refuses an unlicensed tenant without touching it, and reports 207 when another tenant succeeds' {
        $Response = Invoke-Deploy 'nolicence.com', 'contoso.com'
        $Response.StatusCode | Should -Be 207
        $Response.Body.Results[0].state | Should -Be 'error'
        $Response.Body.Results[0].resultText | Should -BeLike 'nolicence.com: web content filtering needs a Microsoft Entra Internet Access licence*'
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0 -ParameterFilter { $TenantFilter -eq 'nolicence.com' }
    }

    It 'reports a conflict or partial failure as a failed tenant, and says when nothing needed changing' {
        Mock Sync-CIPPGSAFilteringProfile { throw [System.ArgumentException]::new("Cannot deploy security profile 'Staff': profile 'Staff' - priority 1000 is already used by profile 'Hand made'") } -ParameterFilter { $TenantFilter -eq 'conflict.com' }
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = 'p'; Results = @([pscustomobject]@{ state = 'error'; resultText = 'Failed to link' }) } } -ParameterFilter { $TenantFilter -eq 'partial.com' }
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = 'p'; Results = @() } } -ParameterFilter { $TenantFilter -eq 'same.com' }

        $Response = Invoke-Deploy 'conflict.com', 'partial.com'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results[0].resultText | Should -BeLike "conflict.com: Cannot deploy*priority 1000 is already used by profile 'Hand made'"

        (Invoke-Deploy 'same.com').Body.Results[0].resultText | Should -Be "same.com: security profile 'Staff' already matches the template"
    }

    It 'expands AllTenants' {
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'a.com' }; [pscustomobject]@{ defaultDomainName = 'b.com' } }
        (Invoke-Deploy 'AllTenants').StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 2 -Exactly
    }
}
