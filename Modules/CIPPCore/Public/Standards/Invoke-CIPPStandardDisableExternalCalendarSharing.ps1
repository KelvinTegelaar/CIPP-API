function Invoke-CIPPStandardDisableExternalCalendarSharing {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    if ($Settings.remediate) {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SharingPolicy' | Where-Object { $_.Default -eq $true } | ForEach-Object {
            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SharingPolicy' -cmdParams @{ Identity = $_.Id ; Enabled = $false } -UseSystemMailbox $true
        }
    }

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SharingPolicy' | Where-Object { $_.Default -eq $true }

        if ($Settings.alert) {
            if ($CurrentInfo.Enabled) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is enabled' -sev Alert
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'External calendar sharing is not enabled' -sev Info
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'ExternalCalendarSharingDisabled' -FieldValue [bool]$CurrentInfo.Enabled -StoreAs bool -Tenant $tenant
        }
    }


}