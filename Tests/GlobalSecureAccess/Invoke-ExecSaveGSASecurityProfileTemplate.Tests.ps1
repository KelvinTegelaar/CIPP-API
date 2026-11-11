BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    foreach ($Helper in 'Get-CippErrorStatusCode', 'ConvertTo-CIPPGSAFilteringRule', 'Compare-CIPPGSAFilteringProfile') { . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper.ps1") }
    . (Join-Path $Folder 'Invoke-ExecSaveGSASecurityProfileTemplate.ps1')

    $script:Id = '11111111-2222-3333-4444-555555555555'
    function Invoke-Save([string]$Id = $script:Id) {
        Invoke-ExecSaveGSASecurityProfileTemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSaveGSASecurityProfileTemplate' }; Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; ID = $Id } })
    }
    function Get-Fqdn([string]$Value) { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.fqdn'; value = $Value } }
    function Get-Row([string]$Partition, [string]$Guid, [hashtable]$Json) { [pscustomobject]@{ PartitionKey = $Partition; RowKey = $Guid; JSON = ($Json | ConvertTo-Json -Depth 10) } }
    function Get-TenantPolicy([string]$Id, [string]$Name, [string]$Domain) {
        [pscustomobject]@{ id = $Id; name = $Name; description = $null; action = 'block'; policyRules = @([pscustomobject]@{ id = "r-$Id"; name = 'sites'; ruleType = 'fqdn'; destinations = @(Get-Fqdn $Domain) }) }
    }
    function Get-Link([string]$PolicyId, [string]$Name, [int]$Priority, [string]$Logging = 'enabled') {
        [pscustomobject]@{ id = "l-$PolicyId"; priority = $Priority; state = 'enabled'; loggingState = $Logging; policy = [pscustomobject]@{ id = $PolicyId; name = $Name } }
    }
}

Describe 'Invoke-ExecSaveGSASecurityProfileTemplate' {
    BeforeEach {
        $script:TenantProfile = [pscustomobject]@{ id = $script:Id; name = 'Staff'; description = 'staff'; priority = 1000; state = 'enabled'; policies = @((Get-Link 'pol-new' 'Block social' 100), (Get-Link 'pol-old' 'Block risky' 200 'disabled')) }
        Mock New-GraphGetRequest { $script:TenantProfile } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        Mock New-GraphGetRequest { (Get-TenantPolicy 'pol-new' 'Block social' 'social.example'), (Get-TenantPolicy 'pol-old' 'Block risky' 'risky.example') } -ParameterFilter { $uri -like '*/filteringPolicies?*' }
        Mock Get-CIPPAzDataTableEntity { Get-Row 'GSAFilteringPolicyTemplate' 'tpl-old' @{ name = 'Block risky'; description = ''; action = 'block'; policyRules = @(@{ name = 'x'; ruleType = 'fqdn'; destinations = @(@{ value = 'risky.example' }) }) } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Get-CIPPAzDataTableEntity { Get-Row 'GSASecurityProfileTemplate' 'prof-1' @{ name = 'Guests'; priority = 2000 } } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'rejects an id that is not a GUID before calling Graph' {
        (Invoke-Save 'nope').StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'creates templates for new policies, reuses a matching one by name, then saves the profile template' {
        $Response = Invoke-Save
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results.resultText) | Should -Be @(
            "Created filtering policy template 'Block social'"
            "Linked the existing filtering policy template 'Block risky'"
            "Created security profile template 'Staff'"
        )
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Stored = $Entity.JSON | ConvertFrom-Json
            $Entity.PartitionKey -eq 'GSAFilteringPolicyTemplate' -and $Stored.name -eq 'Block social' -and $Stored.policyRules[0].destinations[0].value -eq 'social.example' -and -not $Stored.policyRules[0].id
        }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Stored = $Entity.JSON | ConvertFrom-Json
            $Entity.PartitionKey -eq 'GSASecurityProfileTemplate' -and $Stored.name -eq 'Staff' -and $Stored.priority -eq 1000 -and
            $Stored.policies[1].policy.value -eq 'tpl-old' -and $Stored.policies[1].policy.label -eq 'Block risky' -and $Stored.policies[1].loggingState -eq 'disabled' -and
            $Stored.policies[0].policy.value -match '^[0-9a-f-]{36}$'
        }
    }

    It 'refuses and saves nothing when an existing template differs from the tenant policy' {
        Mock New-GraphGetRequest { (Get-TenantPolicy 'pol-new' 'Block social' 'social.example'), (Get-TenantPolicy 'pol-old' 'Block risky' 'changed.example') } -ParameterFilter { $uri -like '*/filteringPolicies?*' }
        $Response = Invoke-Save
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike "*Nothing was saved: filtering policy template 'Block risky' differs from the tenant policy (rule missing: fqdn: risky.example; rule not in the template: fqdn: changed.example)"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses the baseline profile, a profile with no links, and a name or priority another template uses' {
        $script:TenantProfile.priority = 65000
        (Invoke-Save).Body.Results[0].resultText | Should -BeLike '*baseline profile*cannot be saved as a template'
        $script:TenantProfile.priority = 1000
        $script:TenantProfile.policies = @()
        (Invoke-Save).Body.Results[0].resultText | Should -BeLike "*'Staff' links no filtering policies*"
        $script:TenantProfile.policies = @(Get-Link 'pol-new' 'Block social' 100)
        $script:TenantProfile.name = 'GUESTS'
        (Invoke-Save).Body.Results[0].resultText | Should -BeLike "*A security profile template named 'GUESTS' already exists"
        $script:TenantProfile.name = 'Staff'
        $script:TenantProfile.priority = 2000
        $Response = Invoke-Save
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike "*Priority 2000 is already used by security profile template 'Guests'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
