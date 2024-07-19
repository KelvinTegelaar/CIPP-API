function Set-CIPPHideFromGAL {
    [CmdletBinding()]
    param (
        $userid,
        $tenantFilter,
        $APIName = 'Hide From Address List',
        [bool]$HideFromGAL,
        $ExecutingUser
    )
    $Text = if ($HideFromGAL) { 'hidden' } else { 'unhidden' }
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $userid ; HiddenFromAddressListsEnabled = $HideFromGAL }
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($tenantfilter) -message "$($userid) $Text from GAL" -Sev 'Info'
        return "Successfully $Text $($userid) from GAL."
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not hide $($userid) from address list. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not hide $($userid) from address list. Error: $($ErrorMessage.NormalizedError)"
    }
}
