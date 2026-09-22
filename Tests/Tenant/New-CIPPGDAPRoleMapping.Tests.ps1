# Group creation behind GDAP role mappings: a role whose 'M365 GDAP <RoleName>' group already
# exists must be reused rather than recreated, and the rows written to GDAPRoles must carry the
# shape Invoke-ListGDAPRoles and the role templates read back.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/New-CIPPGDAPRoleMapping.ps1'

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $asapp) }

    . $FunctionPath

    $script:WrittenEntities = [System.Collections.Generic.List[object]]::new()
    $script:BulkRequests = $null
}

Describe 'New-CIPPGDAPRoleMapping' {
    BeforeEach {
        $script:WrittenEntities = [System.Collections.Generic.List[object]]::new()
        $script:BulkRequests = $null

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            foreach ($Item in @($Entity)) { $script:WrittenEntities.Add($Item) }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [PSCustomObject]@{ id = 'group-existing'; displayName = 'M365 GDAP User Administrator' }
                [PSCustomObject]@{ id = 'group-suffixed'; displayName = 'M365 GDAP User Administrator - Helpdesk' }
            )
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            $script:BulkRequests = $Requests
            foreach ($Item in $Requests) {
                [PSCustomObject]@{
                    id   = $Item.id
                    body = [PSCustomObject]@{
                        id          = "new-$($Item.id)"
                        displayName = $Item.body.displayName
                    }
                }
            }
        }
    }

    It 'reuses an existing group with the default name' {
        $Result = New-CIPPGDAPRoleMapping -Roles @(
            @{ label = 'User Administrator'; value = 'role-user-admin' }
        )

        Should -Invoke New-GraphBulkRequest -Times 0
        $Result.RoleMappings.Count | Should -Be 1
        $Result.RoleMappings[0].GroupId | Should -Be 'group-existing'
        $Result.Results | Should -Contain 'M365 GDAP User Administrator already exists'
    }

    It 'creates a group for a role that has none' {
        $Result = New-CIPPGDAPRoleMapping -Roles @(
            @{ label = 'Intune Administrator'; value = 'role-intune' }
        )

        $script:BulkRequests.Count | Should -Be 1
        $script:BulkRequests[0].body.displayName | Should -Be 'M365 GDAP Intune Administrator'
        $script:BulkRequests[0].body.mailNickname | Should -Be 'M365GDAPIntuneAdministrator'
        $Result.RoleMappings[0].GroupId | Should -Be 'new-role-intune'
        $Result.RoleMappings[0].RoleName | Should -Be 'Intune Administrator'
        $Result.RoleMappings[0].roleDefinitionId | Should -Be 'role-intune'
        $Result.Results | Should -Contain 'Created M365 GDAP Intune Administrator'
    }

    It 'honours a custom suffix for both reused and created groups' {
        $Result = New-CIPPGDAPRoleMapping -Roles @(
            @{ label = 'User Administrator'; value = 'role-user-admin' }
            @{ label = 'Exchange Administrator'; value = 'role-exchange' }
        ) -CustomSuffix 'Helpdesk'

        $Reused = $Result.RoleMappings | Where-Object -Property RoleName -EQ 'User Administrator'
        $Reused.GroupId | Should -Be 'group-suffixed'
        $Reused.GroupName | Should -Be 'M365 GDAP User Administrator - Helpdesk'

        $script:BulkRequests[0].body.displayName | Should -Be 'M365 GDAP Exchange Administrator - Helpdesk'
        $script:BulkRequests[0].body.mailNickname | Should -Be 'M365GDAPExchangeAdministratorHelpdesk'

        # The suffix is stripped back off for the stored role name.
        $Created = $Result.RoleMappings | Where-Object -Property RoleName -EQ 'Exchange Administrator'
        $Created.GroupName | Should -Be 'M365 GDAP Exchange Administrator - Helpdesk'
    }

    It 'writes GDAPRoles rows in the expected shape' {
        $null = New-CIPPGDAPRoleMapping -Roles @(
            @{ label = 'User Administrator'; value = 'role-user-admin' }
            @{ label = 'Intune Administrator'; value = 'role-intune' }
        )

        $script:WrittenEntities.Count | Should -Be 2
        foreach ($Entity in $script:WrittenEntities) {
            $Entity.PartitionKey | Should -Be 'Roles'
            $Entity.RowKey | Should -Be $Entity.GroupId
            $Entity.Keys | Should -Contain 'RoleName'
            $Entity.Keys | Should -Contain 'GroupName'
            $Entity.Keys | Should -Contain 'roleDefinitionId'
        }
    }

    It 'accepts the catalog shape (Name/ObjectId) as well as label/value' {
        $Result = New-CIPPGDAPRoleMapping -Roles @(
            [PSCustomObject]@{ Name = 'User Administrator'; ObjectId = 'role-user-admin' }
        )

        $Result.RoleMappings[0].GroupId | Should -Be 'group-existing'
        $Result.RoleMappings[0].roleDefinitionId | Should -Be 'role-user-admin'
    }
}
