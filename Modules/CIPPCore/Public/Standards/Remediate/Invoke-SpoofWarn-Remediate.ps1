function Invoke-SpoofWarn-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $status = if ($Settings.enable -and $Settings.disable) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'You cannot both enable and disable the Spoof Warnings setting' -sev Error
        Exit
    } elseif ($Settings.state -eq 'Enabled' -or $Settings.enable) { $true } else { $false }
    try {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ Enabled = $status; }
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Spoofing warnings set to $status." -sev Info

    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set spoofing warnings to $status. Error: $($_.exception.message)" -sev Error
    }
}
