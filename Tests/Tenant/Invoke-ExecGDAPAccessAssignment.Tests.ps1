# Reset Role Mapping must recreate a group whose only assignment was deleted, but not one that was already mapped
# again: Graph keeps the deleted assignment listed next to the live one and rejects a second create.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPGDAPRelationshipId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GDAP/Invoke-ExecGDAPAccessAssignment.ps1')

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $script:GR = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
    $script:EXO = '29232cdf-9323-42fd-ade2-1d097af3e4de'
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter)
        [pscustomobject]@{ RoleMappings = (@(
                    @{ RoleName = 'Global Reader'; GroupName = 'M365 GDAP Global Reader'; GroupId = 'g-reader'; roleDefinitionId = $script:GR }
                    @{ RoleName = 'Exchange Administrator'; GroupName = 'M365 GDAP Exchange Administrator'; GroupId = 'g-exo'; roleDefinitionId = $script:EXO }
                ) | ConvertTo-Json -Compress) }
    }
    function New-GraphGetRequest { param($Uri, $asApp, $NoAuthCheck) @() }
    function Test-CIPPGDAPGroupMappings { param($RoleMappings, $PartnerGroups, [switch]$WriteBack, $TemplateId, $Headers, $PartnerTenantId) [pscustomobject]@{ RoleMappings = $RoleMappings; Results = @($script:GroupResults) } }
    function Test-CippTenantInScope { param($Tenant) $script:ScopeAsked = $Tenant; $script:InScope }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function New-GraphBulkRequest { param($Requests, $NoAuthCheck)
        if ($Requests[0].id -eq 'getRelationship') {
            return @(
                [pscustomobject]@{ id = 'getRelationship'; body = @{ customer = @{ tenantId = 'cust-1' }; accessDetails = @{ unifiedRoles = @(@{ roleDefinitionId = $script:GR }, @{ roleDefinitionId = $script:EXO }) } } }
                [pscustomobject]@{ id = 'getAccessAssignments'; body = @{ value = $script:Assignments } }
            )
        }
        $script:Sent = @($Requests)
        foreach ($R in $Requests) { [pscustomobject]@{ id = $R.id; status = '201' } }
    }
    function New-Assignment($Id, $Group, $Role, $Status) {
        [pscustomobject]@{ id = $Id; status = $Status; '@odata.etag' = 'e'; accessContainer = @{ accessContainerId = $Group }; accessDetails = @{ unifiedRoles = @(@{ roleDefinitionId = $Role }) } }
    }
    function Invoke-Reset {
        Invoke-ExecGDAPAccessAssignment -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecGDAPAccessAssignment' }; Headers = @{}; Query = @{}; Body = [pscustomobject]@{ Action = 'ResetMappings'; Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; RoleTemplateId = 'T' } }) -TriggerMetadata $null
    }
}

Describe 'Invoke-ExecGDAPAccessAssignment ResetMappings' {
    BeforeEach {
        $script:Sent = @()
        $script:InScope = $true
        $script:ScopeAsked = $null
        $script:GroupResults = @()
    }

    It 'does not recreate a group that already has a live assignment next to a deleted one' {
        $script:Assignments = @(
            New-Assignment 'a1' 'g-reader' $script:GR 'deleted'
            New-Assignment 'a2' 'g-reader' $script:GR 'active'
            New-Assignment 'a3' 'g-exo' $script:EXO 'active'
        )
        Invoke-Reset | Out-Null
        @($script:Sent.Where({ $_.method -eq 'POST' })) | Should -HaveCount 0
    }

    It 'recreates a group whose only assignment was deleted' {
        $script:Assignments = @(
            New-Assignment 'a1' 'g-reader' $script:GR 'deleted'
            New-Assignment 'a3' 'g-exo' $script:EXO 'active'
        )
        Invoke-Reset | Out-Null
        @($script:Sent.Where({ $_.method -eq 'POST' }).id) | Should -Be @('create-g-reader')
    }

    It 'deletes the live assignment of a group the template no longer has' {
        $script:Assignments = @(
            New-Assignment 'a2' 'g-reader' $script:GR 'active'
            New-Assignment 'a3' 'g-exo' $script:EXO 'active'
            New-Assignment 'a4' 'g-extra' $script:GR 'active'
        )
        Invoke-Reset | Out-Null
        @($script:Sent.Where({ $_.method -eq 'DELETE' }).id) | Should -Be @('delete-a4')
    }

    It 'refuses a caller whose roles do not include the relationship customer' {
        $script:InScope = $false
        $script:Assignments = @(
            New-Assignment 'a3' 'g-exo' $script:EXO 'active'
            New-Assignment 'a4' 'g-extra' $script:GR 'active'
        )
        $Response = Invoke-Reset
        $Response.StatusCode | Should -Be 403
        $script:ScopeAsked | Should -Be 'cust-1'
        $script:Sent | Should -HaveCount 0
    }

    It 'reports a reserved group the template maps as an error' {
        $script:Assignments = @(
            New-Assignment 'a2' 'g-reader' $script:GR 'active'
            New-Assignment 'a3' 'g-exo' $script:EXO 'active'
        )
        $script:GroupResults = @([pscustomobject]@{ GroupId = 'g-aa'; Status = 'Reserved'; Message = 'reserved' })
        $Response = Invoke-Reset
        @($Response.Body.Results).Where({ $_.resultText -eq 'reserved' }).state | Should -Be 'error'
    }
}
