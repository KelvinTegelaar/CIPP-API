function Set-CippMailboxLocale {
    [CmdletBinding()]
    param (
        $Headers,
        $Locale,
        $Username,
        $APIName = 'Mailbox Locale',
        $TenantFilter,
        # Exchange time zone id, for example 'GMT Standard Time'; left as it is when not given
        $TimeZone
    )

    try {
        # Validate the locale. Also if the locale is not valid, it will throw an exception, not wasting a request.
        if ([System.Globalization.CultureInfo]::GetCultureInfo($Locale).IsNeutralCulture) {
            throw "$Locale is not a valid Locale. Neutral cultures are not supported."
        }

        $RegionalParams = @{
            Identity                  = $Username
            Language                  = $Locale
            LocalizeDefaultFolderName = $true
            DateFormat                = $null
            TimeFormat                = $null
        }
        if ($TimeZone) { $RegionalParams.TimeZone = $TimeZone }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxRegionalConfiguration' -cmdParams $RegionalParams -Anchor $username
        $Result = if ($TimeZone) { "Set locale for $($Username) to $Locale and time zone to $TimeZone" } else { "Set locale for $($Username) to $Locale" }
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set locale for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
