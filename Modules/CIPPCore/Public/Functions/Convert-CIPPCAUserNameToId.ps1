function Convert-CIPPCAUserNameToId {
    <#
    .SYNOPSIS
        Replaces user display names in a CA policy assignment with user object IDs; keywords and GUIDs pass through.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $UserNames,
        $Users,
        [bool]$Strict,
        $TenantFilter,
        $Headers,
        $APIName = 'Create CA Policy'
    )

    $UserIds = [System.Collections.Generic.List[string]]::new()
    $UserNames | ForEach-Object {
        if ($_ -in 'All', 'None', 'GuestsOrExternalUsers') {
            $UserIds.Add($_) # Graph keyword, not a user
        } elseif (Test-IsGuid -String $_) {
            Write-LogMessage -Headers $Headers -API $APIName -message "Already GUID, no need to replace: $_" -Sev 'Debug'
            $UserIds.Add($_) # it's a GUID, so we keep it
        } else {
            $userId = ($Users | Where-Object -Property displayName -EQ $_).id # it's a display name, so we get the user ID
            if ($userId) {
                foreach ($uid in $userId) {
                    Write-Warning "Replaced user name $_ with ID $uid"
                    $null = Write-LogMessage -Headers $Headers -API $APIName -message "Replaced user name $_ with ID $uid" -Sev 'Debug'
                    $UserIds.Add($uid) # add the ID to the list
                }
            } elseif ($Strict) {
                throw [System.Management.Automation.ItemNotFoundException]::new("User '$_' not found in tenant $TenantFilter.")
            } else {
                Write-Warning "User $_ not found in the tenant"
                $null = Write-LogMessage -Headers $Headers -API $APIName -message "CA policy user value '$_' did not match any user in the tenant and was dropped from the policy" -Sev 'Warning'
            }
        }
    }
    return $UserIds
}
