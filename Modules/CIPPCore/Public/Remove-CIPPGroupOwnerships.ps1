function Remove-CIPPGroupOwnerships {
    <#
    .SYNOPSIS
    Removes a user as owner from every group they own, optionally handing ownership to someone else first.

    .DESCRIPTION
    Offboarding step. Lists the groups the user owns and, for each one, adds the replacement owner
    (when one is given) before removing the offboarded user. Microsoft 365 groups must keep at least
    one owner, so the add always runs before the remove: a group the user owns alone is only released
    once the replacement is in place. Groups synced from on-premises Active Directory are reported and
    left alone, since their owners cannot be changed in the cloud.

    Per-group problems are returned as 'Error: ...' lines rather than thrown, matching Remove-CIPPGroups,
    so one group cannot stop the rest of the groups from being processed.

    .PARAMETER Username
    UserPrincipalName of the user being offboarded. Used for logging and as the lookup key when UserID is not given.

    .PARAMETER UserID
    Object id of the user being offboarded.

    .PARAMETER NewOwner
    Object id or UPN of the user to add as owner of every group before the offboarded user is removed. Optional.

    .PARAMETER TenantFilter
    The tenant identifier.

    .PARAMETER APIName
    The API operation name for logging. Default: 'Remove Group Ownership'.

    .PARAMETER Headers
    Request headers for logging. Supplied automatically by the API.
    #>
    [CmdletBinding()]
    param(
        $Username,
        $UserID,
        [string]$NewOwner,
        $TenantFilter,
        $APIName = 'Remove Group Ownership',
        $Headers
    )

    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        if (-not $UserID) {
            $UserInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Username)?`$select=id" -tenantid $TenantFilter
            $UserID = $UserInfo.id
        }

        $OwnedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)/ownedObjects/microsoft.graph.group?`$select=id,displayName,onPremisesSyncEnabled&`$top=999" -tenantid $TenantFilter)

        if ($OwnedGroups.Count -eq 0) {
            $ReturnVal = "$($Username) does not own any groups."
            Write-LogMessage -headers $Headers -API $APIName -message $ReturnVal -Sev 'Info' -tenant $TenantFilter
            return $ReturnVal
        }

        # Resolve the replacement owner once. If one was asked for but cannot be found, do not strip the
        # user: that would leave groups the user owns alone without any owner.
        $NewOwnerId = $null
        $NewOwnerLabel = $null
        if (-not [string]::IsNullOrWhiteSpace($NewOwner)) {
            $Resolved = @(Resolve-CIPPDirectoryId -Identity @($NewOwner) -TenantFilter $TenantFilter) | Select-Object -First 1
            if (-not $Resolved -or -not $Resolved.Resolved -or -not $Resolved.Id) {
                $Message = "Error: Could not find the new group owner '$NewOwner'. No group ownership was changed for $Username."
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter
                $Results.Add($Message)
                return $Results
            }
            if ($Resolved.Id -eq $UserID) {
                $Message = "Error: The new group owner cannot be the user being offboarded ($Username). No group ownership was changed."
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter
                $Results.Add($Message)
                return $Results
            }
            $NewOwnerId = $Resolved.Id
            $NewOwnerLabel = $Resolved.UserPrincipalName ?? $Resolved.DisplayName ?? $NewOwner
        }

        Write-Information "Initiating group ownership removal for user: $Username in tenant: $TenantFilter ($($OwnedGroups.Count) groups)"

        foreach ($Group in $OwnedGroups) {
            $GroupName = $Group.displayName ?? $Group.id

            if ($Group.onPremisesSyncEnabled) {
                $Results.Add("Error: Could not change the owners of group '$GroupName' because it is synced with Active Directory.")
                Write-LogMessage -headers $Headers -API $APIName -message "Could not change the owners of group '$GroupName' for $Username because it is synced with Active Directory." -Sev 'Warning' -tenant $TenantFilter
                continue
            }

            # Set the new owner first; only then release the previous one.
            if ($NewOwnerId) {
                try {
                    $null = Add-CIPPGroupOwner -GroupId $Group.id -Owner @($NewOwnerId) -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                    $Results.Add("Added $NewOwnerLabel as owner of group '$GroupName'")
                } catch {
                    $AddError = $_.Exception.Message
                    if ($AddError -match 'already') {
                        $Results.Add("$NewOwnerLabel is already an owner of group '$GroupName'")
                    } else {
                        $Results.Add("Error: Could not add $NewOwnerLabel as owner of group '$GroupName': $AddError. $Username was left as owner of this group.")
                        continue
                    }
                }
            }

            try {
                $null = Remove-CIPPGroupOwner -GroupId $Group.id -Owner @($UserID) -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                $Results.Add("Successfully removed $Username as owner of group '$GroupName'")
            } catch {
                $Results.Add("Error: Could not remove $Username as owner of group '$GroupName': $($_.Exception.Message)")
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Error removing group ownership for $($Username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $Results.Add("Error removing group ownership for $($Username): $($ErrorMessage.NormalizedError)")
    }

    return $Results
}
