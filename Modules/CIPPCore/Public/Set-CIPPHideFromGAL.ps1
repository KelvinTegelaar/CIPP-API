function Set-CIPPHideFromGAL {
    [CmdletBinding()]
    param (
        $UserId,
        $TenantFilter,
        $APIName = 'Hide From Address List',
        [bool]$HideFromGAL,
        $Headers
    )
    $Text = if ($HideFromGAL) { 'hidden' } else { 'unhidden' }
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserId ; HiddenFromAddressListsEnabled = $HideFromGAL }
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($Tenantfilter) -message "$($UserId) $Text from GAL" -Sev Info
        return "Successfully $Text $($UserId) from GAL."
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not hide $($UserId) from address list. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not hide $($UserId) from address list. Error: $($ErrorMessage.NormalizedError)"
    }
}
