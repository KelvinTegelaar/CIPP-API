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
            $PushParams = @{
                Payload = $Payload
            }
            # New-Push validates ExpireAfterDays as 1-90 and ExpireAfterViews as 1-100 at bind
            # time; an out-of-range saved value would throw here and downgrade every caller to
            # plain text passwords, so drop the setting and warn instead.
            $ExpireAfterDays = $Configuration.ExpireAfterDays -as [int]
            if ($ExpireAfterDays) {
                if ($ExpireAfterDays -ge 1 -and $ExpireAfterDays -le 90) {
                    $PushParams.ExpireAfterDays = $ExpireAfterDays
                } else {
                    Write-LogMessage -API PwPush -Message "Ignoring ExpireAfterDays '$($Configuration.ExpireAfterDays)': PWPush accepts 1 to 90 days" -Sev 'Warning'
                }
            }
            $ExpireAfterViews = $Configuration.ExpireAfterViews -as [int]
            if ($ExpireAfterViews) {
                if ($ExpireAfterViews -ge 1 -and $ExpireAfterViews -le 100) {
                    $PushParams.ExpireAfterViews = $ExpireAfterViews
                } else {
                    Write-LogMessage -API PwPush -Message "Ignoring ExpireAfterViews '$($Configuration.ExpireAfterViews)': PWPush accepts 1 to 100 views" -Sev 'Warning'
                }
            }
            if ($Configuration.DeletableByViewer) { $PushParams.DeletableByViewer = $Configuration.DeletableByViewer }
            # New-Push rejects an account id at bind time when no Authorization header is set, so
            # a stale or placeholder selection saved with bearer auth off must not be passed on.
            if ($Configuration.UseBearerAuth -eq $true -and -not [string]::IsNullOrEmpty($Configuration.AccountId.value)) {
                $PushParams.AccountId = $Configuration.AccountId.value
            }
            if (![string]::IsNullOrEmpty($Configuration.DefaultPassphrase)) { $PushParams.Passphrase = $Configuration.DefaultPassphrase }

            if ($PSCmdlet.ShouldProcess('Create a new PwPush link')) {
                $Link = New-Push @PushParams
                if ($Configuration.RetrievalStep) {
                    return $Link.LinkRetrievalStep -replace '/r/r', '/r'
                }
                return $Link.Link
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
