function Set-CIPPVacationGroupMembership {
    <#
    .SYNOPSIS
        Adds users to a group for a vacation period and removes them again afterwards.
    .DESCRIPTION
        Add puts each user that is not already a member into the group and records who was added in the
        VacationGroupMembers table under the MembershipKey. Remove takes out only those recorded users and deletes
        the record, so memberships that existed before the vacation are never touched.
    .PARAMETER TenantFilter
        The tenant the group lives in.
    .PARAMETER Users
        User principal names of the users going on vacation.
    .PARAMETER GroupId
        The object id of the group.
    .PARAMETER GroupType
        Optional fallback group type passed to the group member helpers.
    .PARAMETER Action
        'Add' at the start of the vacation, 'Remove' at the end.
    .PARAMETER MembershipKey
        Shared key linking the Add and Remove runs of one vacation.
    .PARAMETER Headers
        The headers to include in the request. This is supplied automatically by the API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string[]]$Users,
        [Parameter(Mandatory = $true)]
        [string]$GroupId,
        [string]$GroupType,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action,
        [Parameter(Mandatory = $true)]
        [string]$MembershipKey,
        $Headers,
        [string]$APIName = 'Group Membership Vacation Mode'
    )

    $Table = Get-CIPPTable -tablename 'VacationGroupMembers'

    try {
        if ($Action -eq 'Add') {
            $Group = Get-CIPPGroupType -GroupId $GroupId -TenantFilter $TenantFilter -FallbackGroupType $GroupType
            $CurrentMemberIds = @((New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$($Group.GroupId)/members?`$select=id&`$top=999" -tenantid $TenantFilter).id)
            $ResolvedUsers = @(Resolve-CIPPDirectoryId -Identity $Users -TenantFilter $TenantFilter)

            $AddedUsers = [System.Collections.Generic.List[string]]::new()
            $Messages = [System.Collections.Generic.List[string]]::new()
            foreach ($User in $ResolvedUsers) {
                if ($User.Id -and $CurrentMemberIds -contains $User.Id) {
                    $Messages.Add("$($User.Input) was already a member and will be left in the group.")
                    continue
                }
                # Added one at a time so only users that actually landed are recorded for removal.
                try {
                    $null = Add-CIPPGroupMember -Headers $Headers -GroupType $GroupType -GroupId $GroupId -Member $User.Input -TenantFilter $TenantFilter -APIName $APIName
                    $AddedUsers.Add($User.Input)
                } catch {
                    $Messages.Add("Failed to add $($User.Input): $($_.Exception.Message)")
                }
            }

            Add-CIPPAzDataTableEntity @Table -Entity ([PSCustomObject]@{
                    PartitionKey = $TenantFilter
                    RowKey       = $MembershipKey
                    GroupId      = $GroupId
                    Users        = [string](ConvertTo-Json -InputObject @($AddedUsers) -Compress)
                }) -Force

            $Result = "Added $($AddedUsers.Count) user(s) to group $($Group.DisplayName) for vacation mode. $($Messages -join ' ')".Trim()
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
            return $Result
        }

        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$MembershipKey'"
        if (-not $Entity) {
            # Without a record we cannot tell vacation members from standing ones, so remove nothing.
            $Result = "No vacation membership record found for group $GroupId. No members were removed."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Warning'
            return $Result
        }

        $RecordedUsers = @($Entity.Users | ConvertFrom-Json)
        $Result = if ($RecordedUsers.Count -gt 0) {
            Remove-CIPPGroupMember -Headers $Headers -GroupType $GroupType -GroupId $GroupId -Member $RecordedUsers -TenantFilter $TenantFilter -APIName $APIName
        } else {
            "No users were added to group $GroupId for vacation mode, so none were removed."
        }
        Remove-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to $($Action.ToLower()) vacation group membership for group $($GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        return $Result
    }
}
