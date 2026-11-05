# Tenant onboarding owns 'Excluded onboarded tenants' and finds it by name, and baselines and templates treat
# the placeholder names specially, so the tenant groups API refuses to edit or delete the one and create the others.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) if ($TableName -eq 'TenantGroups') { $script:Existing } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Test-CippAccess { param($Request, [switch]$GroupList) 'AllGroups' }
    function Write-LogMessage { param($API, $tenant, $headers, $message, $Sev) }
    function Clear-CippAccessScopeCache { }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecTenantGroup.ps1')

    function Send($Body) { Invoke-ExecTenantGroup -Request ([pscustomobject]@{ Headers = @{}; Body = [pscustomobject]$Body }) }
    function Set-Existing($Name) { $script:Existing = if ($Name) { [pscustomobject]@{ PartitionKey = 'TenantGroup'; RowKey = 'g1'; Name = $Name; GroupType = 'static' } } }
}

Describe 'Invoke-ExecTenantGroup reserved groups' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
    }

    It 'refuses to <Action> the onboarding exclusion group' -ForEach @(@{ Action = 'Delete' }, @{ Action = 'AddEdit' }) {
        Set-Existing 'Excluded onboarded tenants'
        $Response = Send @{ Action = $Action; groupId = 'g1'; groupName = 'Excluded onboarded tenants'; members = @() }
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses to create a group named <Name>' -ForEach @(
        @{ Name = 'Exported Template' }
        @{ Name = 'template tenant' }
        @{ Name = 'AllTenants' }
        @{ Name = 'Excluded onboarded tenants' }
    ) {
        Set-Existing $null
        (Send @{ Action = 'AddEdit'; groupName = $Name; members = @() }).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses to rename a group to a reserved name' {
        Set-Existing 'Customers'
        (Send @{ Action = 'AddEdit'; groupId = 'g1'; groupName = 'Exported Template'; members = @() }).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'still creates, edits and deletes ordinary groups' {
        Set-Existing $null
        (Send @{ Action = 'AddEdit'; groupName = 'Customers'; members = @() }).StatusCode | Should -Be 200
        Set-Existing 'Customers'
        (Send @{ Action = 'AddEdit'; groupId = 'g1'; groupName = 'Customers renamed'; members = @() }).StatusCode | Should -Be 200
        (Send @{ Action = 'Delete'; groupId = 'g1' }).StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.Name -eq 'Customers renamed' }
    }
}
