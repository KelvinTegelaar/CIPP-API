function Set-CIPPMessageCopy {
    [CmdletBinding()]
    param (
        $UserId,
        [bool]$MessageCopyForSentAsEnabled,
        [bool]$MessageCopyForSendOnBehalfEnabled,
        $TenantFilter,
        $APIName = 'Set message copy for sent',
        $Headers
    )
    try {
        $cmdParams = @{
            Identity                          = $UserId
            MessageCopyForSentAsEnabled       = $MessageCopyForSentAsEnabled
            MessageCopyForSendOnBehalfEnabled = $MessageCopyForSendOnBehalfEnabled

        }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams $cmdParams
        $Result = "Successfully set message copy for 'Send as' as $MessageCopyForSentAsEnabled and 'Sent on behalf' as $MessageCopyForSendOnBehalfEnabled on $($UserId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set message copy for 'Send as' as $MessageCopyForSentAsEnabled and 'Sent on behalf' as $MessageCopyForSendOnBehalfEnabled - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
