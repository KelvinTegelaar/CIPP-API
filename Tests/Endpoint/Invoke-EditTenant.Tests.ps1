# Pester tests for Invoke-EditTenant
#
# Tenant group membership changes are gated on the group being static. Groups created
# before dynamic groups shipped have no GroupType property at all, and the table service
# skips property-missing entities in comparison filters - so the static/dynamic split has
# to happen client-side or those groups can never be added or removed from this endpoint
# (CyberDrain/CIPP#389).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-EditTenant.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-EditTenant.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$TriggerRefresh) }
    function Get-TenantGroups { param([switch]$SkipCache) }
    function Write-LogMessage { param($headers, $API, $tenant, $TenantId, $message, $Sev) }

    . $FunctionPath

    $script:CustomerId = 'f0e1d2c3-0000-0000-0000-000000000001'
    $script:StaticGroupId = '11111111-1111-1111-1111-111111111111'
    $script:LegacyGroupId = '22222222-2222-2222-2222-222222222222'
    $script:DynamicGroupId = '33333333-3333-3333-3333-333333333333'

    function New-EditRequest {
        param($TenantGroups)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'EditTenant' }
            Headers = @{ }
            Body    = [pscustomobject]@{
                customerId   = $script:CustomerId
                tenantAlias  = $null
                tenantGroups = $TenantGroups
            }
            Query   = [pscustomobject]@{ }
        }
    }
}

Describe 'Invoke-EditTenant tenant groups' {
    BeforeEach {
        $script:GroupEntities = @(
            [pscustomobject]@{ PartitionKey = 'TenantGroup'; RowKey = $script:StaticGroupId; Name = 'Whatever - Do this'; GroupType = 'static' }
            # Legacy group: created before dynamic groups existed, no GroupType property at all
            [pscustomobject]@{ PartitionKey = 'TenantGroup'; RowKey = $script:LegacyGroupId; Name = 'Whatever - Exclude that' }
            [pscustomobject]@{ PartitionKey = 'TenantGroup'; RowKey = $script:DynamicGroupId; Name = 'Whatever - Dynamic'; GroupType = 'dynamic' }
        )
        $script:MemberEntities = @()

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-TenantGroups -MockWith { }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = $script:CustomerId; defaultDomainName = 'contoso.onmicrosoft.com'; displayName = 'Contoso' }
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            switch ($Context) {
                'TenantGroups' {
                    if ($Filter -like '*GroupType*') {
                        # Emulate table-service semantics: a comparison filter on GroupType
                        # skips entities that do not carry the property at all
                        $script:GroupEntities | Where-Object { $null -ne $_.PSObject.Properties['GroupType'] -and $_.GroupType -ne 'dynamic' }
                    } else {
                        $script:GroupEntities
                    }
                }
                'TenantGroupMembers' {
                    if ($Filter -like "*'$($script:CustomerId)'*") { $script:MemberEntities } else { @() }
                }
                default { @() }
            }
        }
    }

    It 'adds membership for a legacy group that has no GroupType property' {
        $Request = New-EditRequest -TenantGroups @(
            [pscustomobject]@{ groupId = $script:StaticGroupId; groupName = 'Whatever - Do this' }
            [pscustomobject]@{ groupId = $script:LegacyGroupId; groupName = 'Whatever - Exclude that' }
        )

        $Response = Invoke-EditTenant -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.GroupId -eq $script:StaticGroupId -and $Entity.customerId -eq $script:CustomerId
        }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.GroupId -eq $script:LegacyGroupId -and $Entity.customerId -eq $script:CustomerId
        }
    }

    It 'does not add membership for a dynamic group' {
        $Request = New-EditRequest -TenantGroups @(
            [pscustomobject]@{ groupId = $script:DynamicGroupId; groupName = 'Whatever - Dynamic' }
        )

        $Response = Invoke-EditTenant -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'removes a deselected legacy group that has no GroupType property' {
        $script:MemberEntities = @(
            [pscustomobject]@{
                PartitionKey = 'Member'
                RowKey       = '{0}-{1}' -f $script:LegacyGroupId, $script:CustomerId
                GroupId      = $script:LegacyGroupId
                customerId   = $script:CustomerId
            }
        )
        $Request = New-EditRequest -TenantGroups @(
            [pscustomobject]@{ groupId = $script:StaticGroupId; groupName = 'Whatever - Do this' }
        )

        $Response = Invoke-EditTenant -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.GroupId -eq $script:LegacyGroupId
        }
    }
}
