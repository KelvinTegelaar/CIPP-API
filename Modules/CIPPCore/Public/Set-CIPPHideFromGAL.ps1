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
        $Result = "Successfully $Text $($UserId) from GAL."
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev Info
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set $($UserId) to $Text in GAL. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
