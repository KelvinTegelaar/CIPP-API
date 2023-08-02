function Set-CIPPHideFromGAL {
    [CmdletBinding()]
    param (
        $userid,
        $tenantFilter,
        $APIName = "Hide From Address List",
        [bool]$HideFromGAL,
        $ExecutingUser
    )
    $Text = if ($HideFromGAL) { "hidden" } else { "unhidden" }
    try {
        $Request = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $userid ; HiddenFromAddressListsEnabled = $HideFromGAL }
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($tenantfilter) -message "$($userid) $Text from GAL" -Sev "Info"
        return "Successfully $Text $($userid) from GAL."
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not hide $($userid) from address list" -Sev "Error" -tenant $TenantFilter
        return "Could not hide $($userid) from address list. Error: $($_.Exception.Message)"
    }
}
