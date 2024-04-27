function Invoke-CIPPStandardMessageExpiration {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    $MessageExpiration = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig').messageExpiration

    If ($Settings.remediate) {
        Write-Host 'Time to remediate'
        if ($MessageExpiration -ne '12:00:00') {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportConfig' -cmdParams @{MessageExpiration = '12:00:00' }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set transport configuration message expiration to 12 hours' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set transport configuration message expiration to 12 hours. Error: $ErrorMessage" -sev Debug
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is already set to 12 hours' -sev Info
        }
        
    }
    if ($Settings.alert) {
        if ($MessageExpiration -ne '12:00:00') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is set to 12 hours' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Transport configuration message expiration is not set to 12 hours' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($MessageExpiration -ne '12:00:00') { $MessageExpiration = $false } else { $MessageExpiration = $true }
        Add-CIPPBPAField -FieldName 'messageExpiration' -FieldValue [bool]$MessageExpiration -StoreAs bool -Tenant $tenant
    }
}
