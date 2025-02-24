function Set-CippMailboxLocale {
    [CmdletBinding()]
    param (
        $Headers,
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
        $Result = "Set locale for $($username) to a $locale"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not set locale for $($username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
