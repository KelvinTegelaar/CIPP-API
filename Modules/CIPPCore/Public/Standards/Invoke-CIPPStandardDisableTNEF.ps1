function Invoke-CIPPStandardDisableTNEF {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param ($Tenant, $Settings)
    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RemoteDomain' -cmdParams @{Identity = 'Default' }
    
    if ($Settings.remediate) {
        Write-Host 'Time to remediate'
        
        if ($CurrentState.TNEFEnabled -ne $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RemoteDomain' -cmdParams @{Identity = 'Default'; TNEFEnabled = $false } -useSystemmailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled TNEF for Default Remote Domain' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable TNEF for Default Remote Domain. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is already disabled for Default Remote Domain' -sev Info
        }
    }

    if ($Settings.alert) {
        if ($CurrentState.TNEFEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is disabled for Default Remote Domain' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is not disabled for Default Remote Domain' -sev Alert
        }
    }

    if ($Settings.report) {
        $State = if ($CurrentState.TNEFEnabled -ne $false) { $false } else { $true }
        Add-CIPPBPAField -FieldName 'TNEFDisabled' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }

}