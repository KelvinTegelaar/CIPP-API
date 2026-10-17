function Start-SAMCredentialMonitorTimer {
    <#
    .SYNOPSIS
    Alerts on secrets and certificates added to or removed from the CIPP-SAM app
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-SAMCredentialMonitorTimer', 'Comparing CIPP-SAM credentials')) {
        $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
        if (-not $env:ApplicationID -or $env:ApplicationID -match $PlaceholderPattern) { return }
        try {
            $null = Compare-CIPPSAMCredentialSnapshot
        } catch {
            Write-LogMessage -API 'SAM Credential Monitor' -tenant 'Global' -message "Could not check CIPP-SAM credentials: $($_.Exception.Message)" -Sev 'Warning' -LogData (Get-CippException -Exception $_)
        }
    }
}
