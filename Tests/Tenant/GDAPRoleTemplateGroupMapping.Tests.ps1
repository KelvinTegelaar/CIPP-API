# A role can be delegated through more than one group (for example Global Reader for both the M365 group and
# an Azure subscription management group), so template merges, invite mapping and group recreation must all
# treat each group and role pair on its own.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPGDAPRoleTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPGDAPInviteGroups.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPGDAPGroupMappings.ps1')

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) $script:Rows[$TableName] }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Saved = $Entity }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed = $Entity }
    function New-GraphGetRequest { param($Uri) $script:Assignments }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $NoAuthCheck, [switch]$verbose) $script:Posted.Add(($body | ConvertFrom-Json).accessContainer.accessContainerId); if ($script:FailGroup -and $body -match $script:FailGroup) { throw 'Graph refused the group' } }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $AsApp) $script:BulkIds = @($Requests.id); @() }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    $script:GR = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
    $script:M365Reader = [pscustomobject]@{ RoleName = 'Global Reader'; GroupName = 'M365 GDAP Global Reader'; GroupId = 'g-reader'; roleDefinitionId = $script:GR }
    $script:PimReader = [pscustomobject]@{ RoleName = 'Global Reader'; GroupName = 'PIM Azure Subscription Management'; GroupId = 'g-pim'; roleDefinitionId = $script:GR }
    $script:Exchange = [pscustomobject]@{ RoleName = 'Exchange Administrator'; GroupName = 'M365 GDAP Exchange Administrator'; GroupId = 'g-exo'; roleDefinitionId = '29232cdf-9323-42fd-ade2-1d097af3e4de' }
}

Describe 'GDAP role template group mapping' {
    BeforeEach {
        $script:Rows = @{}
        $script:Saved = $null
        $script:Removed = $null
        $script:Posted = [System.Collections.Generic.List[string]]::new()
        $script:FailGroup = $null
        $script:Assignments = @()
    }

    Context 'Add-CIPPGDAPRoleTemplate merge' {
        BeforeEach {
            $script:Rows['GDAPRoleTemplates'] = @([pscustomobject]@{ RowKey = 'Lannet'; RoleMappings = (@($script:M365Reader) | ConvertTo-Json -Compress -AsArray) })
        }

        It 'keeps a second group added to a role the template already has' {
            Add-CIPPGDAPRoleTemplate -TemplateId 'Lannet' -RoleMappings @($script:PimReader)
            @($script:Saved.RoleMappings | ConvertFrom-Json).GroupId | Should -Be @('g-reader', 'g-pim')
        }

        It 'does not duplicate a group and role pair that is already there' {
            Add-CIPPGDAPRoleTemplate -TemplateId 'Lannet' -RoleMappings @($script:M365Reader)
            @($script:Saved.RoleMappings | ConvertFrom-Json).GroupId | Should -Be @('g-reader')
        }
    }

    Context 'Set-CIPPGDAPInviteGroups' {
        BeforeEach {
            $script:Rows['GDAPInvites'] = [pscustomobject]@{ RowKey = 'rel-1'; RoleMappings = (@($script:Exchange, $script:M365Reader, $script:PimReader) | ConvertTo-Json -Compress) }
            $script:Relationship = [pscustomobject]@{ id = 'rel-1'; customer = @{ displayName = 'Contoso' } }
            Mock Start-Sleep {}
        }

        It 'maps both groups that share a role and clears the invite' {
            Set-CIPPGDAPInviteGroups -Relationship $script:Relationship | Should -BeTrue
            $script:Posted | Should -Be @('g-exo', 'g-reader', 'g-pim')
            $script:Removed | Should -Not -BeNullOrEmpty
        }

        It 'maps the remaining groups after one fails and keeps the invite for a retry' {
            $script:FailGroup = 'g-exo'
            Set-CIPPGDAPInviteGroups -Relationship $script:Relationship | Should -BeFalse
            $script:Posted | Should -Be @('g-exo', 'g-reader', 'g-pim')
            $script:Removed | Should -BeNullOrEmpty
        }

        It 'only maps the groups still missing on a retry' {
            $script:Assignments = @([pscustomobject]@{ id = 'a1'; accessContainer = @{ accessContainerId = 'g-reader' } })
            Set-CIPPGDAPInviteGroups -Relationship $script:Relationship | Should -BeTrue
            $script:Posted | Should -Be @('g-exo', 'g-pim')
        }

        It 'maps a group again when its earlier assignment was deleted' {
            $script:Assignments = @(
                [pscustomobject]@{ id = 'a1'; status = 'deleted'; accessContainer = @{ accessContainerId = 'g-reader' } }
                [pscustomobject]@{ id = 'a2'; status = 'active'; accessContainer = @{ accessContainerId = 'g-exo' } }
            )
            Set-CIPPGDAPInviteGroups -Relationship $script:Relationship | Should -BeTrue
            $script:Posted | Should -Be @('g-reader', 'g-pim')
        }
    }

    Context 'Test-CIPPGDAPGroupMappings recreation' {
        It 'gives each missing group its own batch request when they share a role' {
            Test-CIPPGDAPGroupMappings -RoleMappings @($script:M365Reader, $script:PimReader) -PartnerGroups @() -CreateMissing | Out-Null
            $script:BulkIds | Should -HaveCount 2
            @($script:BulkIds | Select-Object -Unique) | Should -HaveCount 2
        }
    }
}
