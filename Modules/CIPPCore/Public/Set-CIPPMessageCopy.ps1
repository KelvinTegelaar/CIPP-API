function Set-CIPPMessageCopy {
    [CmdletBinding()]
    param (
        $userid,
        $MessageCopyForSentAsEnabled,
        $TenantFilter,
        $APIName = 'Manage OneDrive Access',
        $Headers
    )
    Try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $userid; MessageCopyForSentAsEnabled = $MessageCopyForSentAsEnabled }
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantfilter) -message "Successfully set MessageCopyForSentAsEnabled as $MessageCopyForSentAsEnabled on $($userid)." -Sev 'Info'
        return "Successfully set MessageCopyForSentAsEnabled as $MessageCopyForSentAsEnabled on $($userid)."
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantfilter) -message "set MessageCopyForSentAsEnabled to $MessageCopyForSentAsEnabled failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "set MessageCopyForSentAsEnabled to $MessageCopyForSentAsEnabled failed - $($ErrorMessage.NormalizedError)"
    }
}
