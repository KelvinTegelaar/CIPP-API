function Invoke-ExecScheduleGroupMembershipVacation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    .SYNOPSIS
        Schedule group membership for a vacation period
    .DESCRIPTION
        Adds the selected users to each selected group at the start date and removes them again at the end date. Users who were already members of a group are left untouched.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.tenantFilter
        # The users going on vacation
        $Users = @($Request.Body.Users)
        # The groups to add the users to, as { value = group id; label = display name }
        $Groups = @($Request.Body.Groups | Where-Object { $_.value })
        # Unix timestamp for when the users are added
        $StartDate = $Request.Body.startDate
        # Unix timestamp for when the users are removed
        $EndDate = $Request.Body.endDate

        $UserUPNs = @($Users | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value ?? $_ })

        if ($UserUPNs.Count -eq 0) {
            throw 'At least one user is required.'
        }
        if ($Groups.Count -eq 0) {
            throw 'At least one group is required.'
        }
        if (-not $StartDate -or -not $EndDate) {
            throw 'A start date and end date are required.'
        }

        $UserDisplay = ($UserUPNs | Select-Object -First 3) -join ', '
        if ($UserUPNs.Count -gt 3) { $UserDisplay += " (+$($UserUPNs.Count - 3) more)" }

        foreach ($Group in $Groups) {
            $GroupLabel = $Group.label ?? $Group.value
            # Links the add and remove runs so the remove only takes out the users the add put in.
            $MembershipKey = [guid]::NewGuid().ToString()

            Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Add Group Membership Vacation Mode: $GroupLabel - $UserDisplay"
                    Command       = @{ value = 'Set-CIPPVacationGroupMembership'; label = 'Set-CIPPVacationGroupMembership' }
                    Parameters    = [PSCustomObject]@{
                        TenantFilter  = $TenantFilter
                        Users         = $UserUPNs
                        GroupId       = $Group.value
                        GroupType     = $Group.addedFields.groupType
                        Action        = 'Add'
                        MembershipKey = $MembershipKey
                    }
                    ScheduledTime = [int64]$StartDate
                    PostExecution = $Request.Body.postExecution
                    Reference     = $Request.Body.reference
                }) -hidden $false

            Add-CIPPScheduledTask -Task ([PSCustomObject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Remove Group Membership Vacation Mode: $GroupLabel - $UserDisplay"
                    Command       = @{ value = 'Set-CIPPVacationGroupMembership'; label = 'Set-CIPPVacationGroupMembership' }
                    Parameters    = [PSCustomObject]@{
                        TenantFilter  = $TenantFilter
                        Users         = $UserUPNs
                        GroupId       = $Group.value
                        GroupType     = $Group.addedFields.groupType
                        Action        = 'Remove'
                        MembershipKey = $MembershipKey
                    }
                    ScheduledTime = [int64]$EndDate
                    PostExecution = $Request.Body.postExecution
                    Reference     = $Request.Body.reference
                }) -hidden $false
        }

        $GroupDisplay = ($Groups | ForEach-Object { $_.label ?? $_.value }) -join ', '
        $Result = "Successfully scheduled group membership vacation mode for $UserDisplay in $GroupDisplay."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to schedule group membership vacation mode: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
