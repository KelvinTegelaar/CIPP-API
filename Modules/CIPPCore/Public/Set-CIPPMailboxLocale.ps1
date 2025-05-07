function Set-CippMailboxLocale {
    [CmdletBinding()]
    param (
        $Headers,
        $Locale,
        $Username,
        $APIName = 'Mailbox Locale',
        $TenantFilter
    )

    try {
        # Validate the locale. Also if the locale is not valid, it will throw an exception, not wasting a request.
        if ([System.Globalization.CultureInfo]::GetCultureInfo($Locale).IsNeutralCulture) {
            throw "$Locale is not a valid Locale. Neutral cultures are not supported."
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxRegionalConfiguration' -cmdParams @{
            Identity                  = $Username
            Language                  = $Locale
            LocalizeDefaultFolderName = $true
            DateFormat                = $null
            TimeFormat                = $null
        } -Anchor $username
        $Result = "Set locale for $($Username) to $Locale"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set locale for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
