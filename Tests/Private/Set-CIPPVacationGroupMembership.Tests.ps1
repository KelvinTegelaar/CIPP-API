# Pester tests for Set-CIPPVacationGroupMembership.
#
# Vacation Mode schedules an 'Add' at the start date and a 'Remove' at the end date, linked by a
# MembershipKey. The remove must only take out users the add actually put in, so a standing
# membership is never stripped when the vacation ends.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPVacationGroupMembership.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Set-CIPPVacationGroupMembership.ps1 at $FunctionPath" }

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CIPPGroupType { param($GroupId, $TenantFilter, $FallbackGroupType) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Resolve-CIPPDirectoryId { param($Identity, $TenantFilter) }
    function Add-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Remove-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Set-CIPPVacationGroupMembership' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPGroupMember -MockWith { 'added' }
        Mock -CommandName Remove-CIPPGroupMember -MockWith { 'removed' }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        $script:SavedRows = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:SavedRows.Add($Entity) }
    }

    Context 'Add at the start of the vacation' {
        BeforeEach {
            Mock -CommandName Get-CIPPGroupType -MockWith {
                [pscustomobject]@{ GroupId = 'group-1'; DisplayName = 'Travel'; GroupType = 'Security'; IsExchangeBacked = $false }
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @([pscustomobject]@{ id = 'id-existing' }) }
            Mock -CommandName Resolve-CIPPDirectoryId -MockWith {
                @(
                    [pscustomobject]@{ Input = 'existing@contoso.com'; Id = 'id-existing'; Resolved = $true }
                    [pscustomobject]@{ Input = 'new@contoso.com'; Id = 'id-new'; Resolved = $true }
                )
            }
        }

        It 'skips users who are already members and records only the users it added' {
            $null = Set-CIPPVacationGroupMembership -TenantFilter 'contoso.com' -Users @('existing@contoso.com', 'new@contoso.com') `
                -GroupId 'group-1' -Action 'Add' -MembershipKey 'key-1'

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly
            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $Member -eq 'new@contoso.com' -and $GroupId -eq 'group-1' }
            $script:SavedRows.Count | Should -Be 1
            $script:SavedRows[0].PartitionKey | Should -Be 'contoso.com'
            $script:SavedRows[0].RowKey | Should -Be 'key-1'
            $script:SavedRows[0].GroupId | Should -Be 'group-1'
            @($script:SavedRows[0].Users | ConvertFrom-Json) | Should -Be @('new@contoso.com')
        }

        It 'does not record a user whose add failed' {
            Mock -CommandName Add-CIPPGroupMember -MockWith { throw 'Graph said no' }

            $Result = Set-CIPPVacationGroupMembership -TenantFilter 'contoso.com' -Users @('existing@contoso.com', 'new@contoso.com') `
                -GroupId 'group-1' -Action 'Add' -MembershipKey 'key-1'

            @($script:SavedRows[0].Users | ConvertFrom-Json).Count | Should -Be 0
            $Result | Should -BeLike '*Failed to add new@contoso.com*'
        }
    }

    Context 'Remove at the end of the vacation' {
        It 'removes only the recorded users and deletes the record' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'key-1'; GroupId = 'group-1'; Users = '["new@contoso.com"]' }
            }

            $null = Set-CIPPVacationGroupMembership -TenantFilter 'contoso.com' -Users @('existing@contoso.com', 'new@contoso.com') `
                -GroupId 'group-1' -Action 'Remove' -MembershipKey 'key-1'

            Should -Invoke Remove-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
                @($Member).Count -eq 1 -and $Member[0] -eq 'new@contoso.com' -and $GroupId -eq 'group-1'
            }
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'key-1' }
        }

        It 'removes nothing and warns when there is no record' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }

            $Result = Set-CIPPVacationGroupMembership -TenantFilter 'contoso.com' -Users @('existing@contoso.com') `
                -GroupId 'group-1' -Action 'Remove' -MembershipKey 'key-missing'

            Should -Invoke Remove-CIPPGroupMember -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' }
            $Result | Should -BeLike '*No members were removed*'
        }
    }
}
