# The tenant selector lists groups with ?TenantSelector=true. A caller whose roles block tenant groups in the selector
# gets none there, but still sees them everywhere else groups are picked (assignments, role scopes).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListTenantGroups.ps1' -File)[0].FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-TenantGroups { [CmdletBinding()] param($GroupId, [switch]$SkipCache) }
    function Test-CippAllTenantsBlocked { [CmdletBinding()] param([string[]]$Roles, [switch]$TenantGroups) }
    function Get-CIPPFeatureFlag { [CmdletBinding()] param($Id) }

    . $FunctionPath

    function script:Get-GroupList {
        param([hashtable]$Query = @{})
        @((Invoke-ListTenantGroups -Request ([pscustomobject]@{ Query = [pscustomobject]$Query; Body = $null; Headers = @{} }) -TriggerMetadata $null).Body.Results)
    }
}

Describe 'Invoke-ListTenantGroups for the tenant selector' {
    BeforeEach {
        Mock Get-TenantGroups { [pscustomobject]@{ Id = 'g1'; Name = 'Group One' } }
        Mock Get-CIPPFeatureFlag { [pscustomobject]@{ Id = 'TenantGroupSelector'; Enabled = $true } }
    }

    It 'lists no groups in the selector when the caller''s roles block them' {
        Mock Test-CippAllTenantsBlocked { $TenantGroups.IsPresent }
        (Get-GroupList @{ TenantSelector = 'true' }).Count | Should -Be 0
    }

    It 'still lists groups outside the selector for that caller' {
        Mock Test-CippAllTenantsBlocked { $TenantGroups.IsPresent }
        (Get-GroupList).Count | Should -Be 1
    }

    It 'lists no groups in the selector while the TenantGroupSelector feature flag is off' {
        Mock Test-CippAllTenantsBlocked { $false }
        Mock Get-CIPPFeatureFlag { [pscustomobject]@{ Id = 'TenantGroupSelector'; Enabled = $false } }
        (Get-GroupList @{ TenantSelector = 'true' }).Count | Should -Be 0
        (Get-GroupList).Count | Should -Be 1
    }

    It 'lists groups in the selector when nothing blocks them' {
        Mock Test-CippAllTenantsBlocked { $false }
        (Get-GroupList @{ TenantSelector = 'true' })[0].Id | Should -Be 'g1'
    }
}
