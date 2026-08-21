function New-PwPushLink {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        $Payload,
        # Rethrow creation failures instead of collapsing them into $false. The password flows
        # rely on the silent fallback; the extension test uses this to show the real error.
        [switch]$ThrowOnError
    )

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ConfigEntity = Get-CIPPAzDataTableEntity @Table

        # Check if the config entity exists and has a config property
        if (-not $ConfigEntity -or [string]::IsNullOrEmpty($ConfigEntity.config)) {
            return $false
        }

        # Safely parse the JSON configuration
        try {
            $ParsedConfig = $ConfigEntity.config | ConvertFrom-Json -ErrorAction Stop
            $Configuration = $ParsedConfig.PWPush
        } catch {
            return $false
        }

        # Check if PWPush section exists in configuration
        if (-not $Configuration) {
            return $false
        }

        # Check if PwPush is enabled
        if ($Configuration.Enabled -ne $true) {
            return $false
        }

        # Proceed with creating the PwPush link
        try {
            Set-PwPushConfig -Configuration $Configuration -FullConfiguration $ParsedConfig
            $PasswordValues = @{
                kind    = 'text'
                payload = [string]$Payload
            }
            # The API accepts 1-90 days and 1-100 views; an out-of-range saved value would fail
            # the whole push and downgrade every caller to plain text passwords, so drop the
            # setting and warn instead.
            $ExpireAfterDays = $Configuration.ExpireAfterDays -as [int]
            if ($ExpireAfterDays) {
                if ($ExpireAfterDays -ge 1 -and $ExpireAfterDays -le 90) {
                    $PasswordValues.expire_after_days = $ExpireAfterDays
                } else {
                    Write-LogMessage -API PwPush -Message "Ignoring ExpireAfterDays '$($Configuration.ExpireAfterDays)': PWPush accepts 1 to 90 days" -Sev 'Warning'
                }
            }
            $ExpireAfterViews = $Configuration.ExpireAfterViews -as [int]
            if ($ExpireAfterViews) {
                if ($ExpireAfterViews -ge 1 -and $ExpireAfterViews -le 100) {
                    $PasswordValues.expire_after_views = $ExpireAfterViews
                } else {
                    Write-LogMessage -API PwPush -Message "Ignoring ExpireAfterViews '$($Configuration.ExpireAfterViews)': PWPush accepts 1 to 100 views" -Sev 'Warning'
                }
            }
            if ($Configuration.DeletableByViewer) { $PasswordValues.deletable_by_viewer = $true }
            if (![string]::IsNullOrEmpty($Configuration.DefaultPassphrase)) { $PasswordValues.passphrase = $Configuration.DefaultPassphrase }
            $PushBody = @{ password = $PasswordValues }
            # An account id is only valid on an authenticated session, so a stale or placeholder
            # selection saved while bearer auth is off must not be passed on.
            if ($Configuration.UseBearerAuth -eq $true -and -not [string]::IsNullOrEmpty($Configuration.AccountId.value)) {
                $PushBody.account_id = $Configuration.AccountId.value
            }

            if ($PSCmdlet.ShouldProcess('Create a new PwPush link')) {
                # POST through the module's internal API helper so its auth headers, user agent
                # and base URL are reused, but skip New-Push: its PasswordPush class types
                # account_id as [int] while pwpush.com now issues string ids ('acct_...'), so
                # the response conversion throws away the link on every authenticated push.
                $Response = & (Get-Module PassPushPosh) {
                    param($Body)
                    Invoke-PasswordPusherAPI -Endpoint 'p.json' -Method Post -Body $Body -ErrorAction Stop
                } $PushBody
                $Link = if (![string]::IsNullOrEmpty($Response.json_url)) {
                    $Response.json_url -replace '\.json$', ''
                } elseif (![string]::IsNullOrEmpty($Response.html_url)) {
                    $Response.html_url -replace '/r$', ''
                } else {
                    # Deliberately not including the response: it echoes the pushed payload
                    throw 'PWPush API response did not contain a link'
                }
                if ($Configuration.RetrievalStep) {
                    return "$Link/r" -replace '/r/r$', '/r'
                }
                return $Link
            }
        } catch {
            $LogData = [PSCustomObject]@{
                'Response'  = if ($Link) { $Link } else { 'No response' }
                'Exception' = Get-CippException -Exception $_
            }
            Write-LogMessage -API PwPush -Message "Failed to create a new PwPush link: $($_.Exception.Message)" -Sev 'Error' -LogData $LogData
            if ($ThrowOnError) { throw }
            Write-LogMessage -API PwPush -Message "Continuing without PwPush link due to error" -sev 'Warning'
            return $false
        }
    } catch {
        Write-LogMessage -API PwPush -Message "Unexpected error in PwPush configuration handling: $($_.Exception.Message)" -Sev 'Error'
        if ($ThrowOnError) { throw }
        return $false
    }
}
