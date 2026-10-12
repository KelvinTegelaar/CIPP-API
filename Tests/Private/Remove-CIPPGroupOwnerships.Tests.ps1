# Pester tests for Remove-CIPPGroupOwnerships.
#
# The offboarding step behind 'Remove group ownership'. It lists the groups a user owns and, per
# group, adds the replacement owner BEFORE removing the offboarded user - a Microsoft 365 group must
# always keep one owner, so the order is the whole point. Per-group problems come back as
# 'Error: ...' lines (Push-CIPPOffboardingTask marks the step failed on those) instead of throwing,
# so one bad group does not stop the others.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPGroupOwnerships.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPGroupOwnerships.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Resolve-CIPPDirectoryId { param($Identity, $TenantFilter) }
    function Add-CIPPGroupOwner { param($Headers, $GroupId, $Owner, $TenantFilter, $APIName) }
    function Remove-CIPPGroupOwner { param($Headers, $GroupId, $Owner, $TenantFilter, $APIName) }

    . $FunctionPath

    function New-OwnedGroup {
        param([string]$Id, [string]$Name, [bool]$Synced = $false)
        [pscustomobject]@{ id = $Id; displayName = $Name; onPremisesSyncEnabled = $Synced }
    }
}

Describe 'Remove-CIPPGroupOwnerships' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPGroupOwner -MockWith { 'added' }
        Mock -CommandName Remove-CIPPGroupOwner -MockWith { 'removed' }
        Mock -CommandName Resolve-CIPPDirectoryId -MockWith {
            param($Identity, $TenantFilter)
            foreach ($raw in @($Identity)) {
                switch ($raw) {
                    'boss@contoso.com' { [pscustomobject]@{ Input = $raw; Id = 'boss-guid'; UserPrincipalName = 'boss@contoso.com'; DisplayName = 'Boss'; Resolved = $true } }
                    'leaver-guid' { [pscustomobject]@{ Input = $raw; Id = 'leaver-guid'; UserPrincipalName = 'leaver@contoso.com'; DisplayName = 'Leaver'; Resolved = $true } }
                    default { [pscustomobject]@{ Input = $raw; Id = $null; UserPrincipalName = $null; DisplayName = $null; Resolved = $false } }
                }
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid)
            if ($uri -match '/ownedObjects/') {
                return @(
                    (New-OwnedGroup -Id 'g1' -Name 'Sales'),
                    (New-OwnedGroup -Id 'g2' -Name 'Marketing')
                )
            }
            return $null
        }
    }

    It 'reports when the user owns no groups and touches nothing' {
        Mock -CommandName New-GraphGetRequest -MockWith { @() }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -TenantFilter 'contoso.com'

        $Result | Should -Be 'leaver@contoso.com does not own any groups.'
        Should -Invoke -CommandName Add-CIPPGroupOwner -Times 0 -Exactly
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 0 -Exactly
    }

    It 'adds the new owner to each group before removing the offboarded user' {
        $Script:CallLog = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName Add-CIPPGroupOwner -MockWith { param($GroupId, $Owner) $Script:CallLog.Add("add:$($GroupId):$($Owner -join ',')"); 'added' }
        Mock -CommandName Remove-CIPPGroupOwner -MockWith { param($GroupId, $Owner) $Script:CallLog.Add("remove:$($GroupId):$($Owner -join ',')"); 'removed' }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'boss@contoso.com' -TenantFilter 'contoso.com'

        $Script:CallLog | Should -Be @('add:g1:boss-guid', 'remove:g1:leaver-guid', 'add:g2:boss-guid', 'remove:g2:leaver-guid')
        @($Result | Where-Object { $_ -match '^Error' }).Count | Should -Be 0
        $Result | Should -Contain "Added boss@contoso.com as owner of group 'Sales'"
        $Result | Should -Contain "Successfully removed leaver@contoso.com as owner of group 'Sales'"
    }

    It 'only removes the offboarded user when no new owner is given' {
        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Add-CIPPGroupOwner -Times 0 -Exactly
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 2 -Exactly
        @($Result | Where-Object { $_ -match '^Error' }).Count | Should -Be 0
    }

    It 'leaves the user as owner of a group when the new owner could not be added there' {
        Mock -CommandName Add-CIPPGroupOwner -MockWith {
            param($GroupId)
            if ($GroupId -eq 'g1') { throw 'Failed to add owner boss@contoso.com to group Sales - Insufficient privileges' }
            'added'
        }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'boss@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g2' }
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 0 -Exactly -ParameterFilter { $GroupId -eq 'g1' }
        ($Result | Where-Object { $_ -match "^Error: Could not add boss@contoso.com as owner of group 'Sales'" }) | Should -Not -BeNullOrEmpty
    }

    It 'treats the new owner already owning a group as fine and still removes the user' {
        Mock -CommandName Add-CIPPGroupOwner -MockWith { throw 'Failed to add boss@contoso.com (already an owner).' }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'boss@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 2 -Exactly
        @($Result | Where-Object { $_ -match '^Error' }).Count | Should -Be 0
        $Result | Should -Contain "boss@contoso.com is already an owner of group 'Sales'"
    }

    It 'returns an error line for a group that could not be released and carries on with the rest' {
        Mock -CommandName Remove-CIPPGroupOwner -MockWith {
            param($GroupId)
            if ($GroupId -eq 'g1') { throw 'The group must have at least one owner, hence this owner cannot be removed.' }
            'removed'
        }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 2 -Exactly
        ($Result | Where-Object { $_ -match "^Error: Could not remove leaver@contoso.com as owner of group 'Sales'" }) | Should -Not -BeNullOrEmpty
        $Result | Should -Contain "Successfully removed leaver@contoso.com as owner of group 'Marketing'"
    }

    It 'skips groups synced from Active Directory' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @((New-OwnedGroup -Id 'g1' -Name 'Sales' -Synced $true), (New-OwnedGroup -Id 'g2' -Name 'Marketing'))
        }

        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'boss@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Add-CIPPGroupOwner -Times 0 -Exactly -ParameterFilter { $GroupId -eq 'g1' }
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 0 -Exactly -ParameterFilter { $GroupId -eq 'g1' }
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g2' }
        ($Result | Where-Object { $_ -match "^Error: Could not change the owners of group 'Sales'" }) | Should -Not -BeNullOrEmpty
    }

    It 'changes nothing when the new owner cannot be found' {
        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'nobody@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Add-CIPPGroupOwner -Times 0 -Exactly
        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 0 -Exactly
        @($Result)[0] | Should -Match '^Error: Could not find the new group owner'
    }

    It 'refuses the offboarded user as their own replacement' {
        $Result = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -UserID 'leaver-guid' -NewOwner 'leaver-guid' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 0 -Exactly
        @($Result)[0] | Should -Match '^Error: The new group owner cannot be the user being offboarded'
    }

    It 'looks the user id up from the UPN when none is given' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri)
            if ($uri -match '/users/leaver@contoso.com\?') { return [pscustomobject]@{ id = 'leaver-guid' } }
            if ($uri -match '/users/leaver-guid/ownedObjects/') { return @((New-OwnedGroup -Id 'g1' -Name 'Sales')) }
            throw "Unexpected uri $uri"
        }

        $null = Remove-CIPPGroupOwnerships -Username 'leaver@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke -CommandName Remove-CIPPGroupOwner -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g1' -and $Owner -contains 'leaver-guid' }
    }
}
