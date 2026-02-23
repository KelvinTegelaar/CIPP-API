function New-PwPushLink {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        $Payload
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
            Set-PwPushConfig -Configuration $Configuration
            $PushParams = @{
                Payload = $Payload
            }
            if ($Configuration.ExpireAfterDays) { $PushParams.ExpireAfterDays = $Configuration.ExpireAfterDays }
            if ($Configuration.ExpireAfterViews) { $PushParams.ExpireAfterViews = $Configuration.ExpireAfterViews }
            if ($Configuration.DeletableByViewer) { $PushParams.DeletableByViewer = $Configuration.DeletableByViewer }
            if ($Configuration.AccountId) { $PushParams.AccountId = $Configuration.AccountId.value }

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
            Write-LogMessage -API PwPush -Message "Continuing without PwPush link due to error" -sev 'Warn'
            return $false
        }
    } catch {
        Write-LogMessage -API PwPush -Message "Unexpected error in PwPush configuration handling: $($_.Exception.Message)" -Sev 'Error'
        return $false
    }
}
