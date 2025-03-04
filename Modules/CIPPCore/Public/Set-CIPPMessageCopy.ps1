function Set-CIPPMessageCopy {
    [CmdletBinding()]
    param (
        $userid,
        [bool]$MessageCopyForSentAsEnabled,
        $TenantFilter,
        $APIName = 'Manage OneDrive Access',
        $Headers
    )
    Try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $userid; MessageCopyForSentAsEnabled = $MessageCopyForSentAsEnabled }
        $Result = "Successfully set MessageCopyForSentAsEnabled as $MessageCopyForSentAsEnabled on $($userid)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set MessageCopyForSentAsEnabled to $MessageCopyForSentAsEnabled - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
