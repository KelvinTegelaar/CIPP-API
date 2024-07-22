function Set-CippMailboxLocale {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $locale,
        $username,
        $APIName = 'Mailbox Locale',
        $TenantFilter
    )

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxRegionalConfiguration' -cmdParams @{
            Identity                  = $username
            Language                  = $locale
            LocalizeDefaultFolderName = $true
        } -Anchor $username
        Write-LogMessage -user $ExecutingUser -API $APIName -message "set locale for $($username) to a $locale" -Sev 'Info' -tenant $TenantFilter
        return "set locale for $($username) to a $locale"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not set locale for $($username). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return  "Could not set locale for $username. Error: $($ErrorMessage.NormalizedError)"
    }
}
