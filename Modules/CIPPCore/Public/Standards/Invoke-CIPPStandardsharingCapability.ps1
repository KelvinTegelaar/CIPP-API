function Invoke-CIPPStandardsharingCapability {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'sharingCapability' -FieldValue $CurrentInfo.sharingCapability -StoreAs string -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.sharingCapability) -or $Settings.sharingCapability -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'sharingCapability: Invalid sharingCapability parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.sharingCapability -eq $Settings.Level) {
            Write-Host "Sharing level is already set to $($Settings.Level)"
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Sharing level is already set to $($Settings.Level)" -sev Info
        } else {
            Write-Host "Setting sharing level to $($Settings.Level) from $($CurrentInfo.sharingCapability)"
            try {
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body "{`"sharingCapability`":`"$($Settings.Level)`"}" -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set sharing level to $($Settings.Level) from $($CurrentInfo.sharingCapability)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set sharing level to $($Settings.Level): $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.sharingCapability -eq $Settings.Level) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Sharing level is set to $($Settings.Level)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Sharing level is not set to $($Settings.Level)" -sev Alert
        }
    }
}
