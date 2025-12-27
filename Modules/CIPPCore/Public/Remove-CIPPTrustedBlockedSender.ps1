function Remove-CIPPTrustedBlockedSender {
    [CmdletBinding()]
    param (
        [string]$UserPrincipalName,
        [string]$TenantFilter,
        [string]$APIName = 'Trusted/Blocked Sender Removal',
        $Headers,
        [string]$TypeProperty,
        [string]$Value
    )

    try {

        # Set the updated configuration
        $SetParams = @{
            Identity      = $UserPrincipalName
            $TypeProperty = @{'@odata.type' = '#Exchange.GenericHashTable'; Remove = $Value }
        }

        $null = New-ExoRequest -Anchor $UserPrincipalName -tenantid $TenantFilter -cmdlet 'Set-MailboxJunkEmailConfiguration' -cmdParams $SetParams
        $Message = "Successfully removed '$Value' from $TypeProperty for $($UserPrincipalName)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to remove junk email configuration entry for $($UserPrincipalName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
