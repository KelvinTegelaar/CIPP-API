function Invoke-CIPPStandardDisableExternalCalendarSharing {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SharingPolicy' | Where-Object { $_.Default -eq $true }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.Enabled) {
            $CurrentInfo | ForEach-Object {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SharingPolicy' -cmdParams @{ Identity = $_.Id ; Enabled = $false } -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully disabled external calendar sharing for the policy $($_.Name)" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable external calendar sharing for the policy $($_.Name). Error: $ErrorMessage" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is already disabled' -sev Info

        }

    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.Enabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentInfo.Enabled = -not $CurrentInfo.Enabled
        Add-CIPPBPAField -FieldName 'ExternalCalendarSharingDisabled' -FieldValue $CurrentInfo.Enabled -StoreAs bool -Tenant $tenant
    }
}