function Invoke-CIPPStandardsharingCapability {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    sharingCapability
    .CAT
    SharePoint Standards
    .TAG
    "highimpact"
    "CIS"
    .HELPTEXT
    Sets the default sharing level for OneDrive and Sharepoint. This is a tenant wide setting and overrules any settings set on the site level
    .ADDEDCOMPONENT
    {"type":"Select","label":"Select Sharing Level","name":"standards.sharingCapability.Level","values":[{"label":"Users can share only with people in the organization. No external sharing is allowed.","value":"disabled"},{"label":"Users can share with new and existing guests. Guests must sign in or provide a verification code.","value":"externalUserSharingOnly"},{"label":"Users can share with anyone by using links that do not require sign-in.","value":"externalUserAndGuestSharing"},{"label":"Users can share with existing guests (those already in the directory of the organization).","value":"existingExternalUserSharingOnly"}]}
    .LABEL
    Set Sharing Level for OneDrive and Sharepoint
    .IMPACT
    High Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaAdminSharepointSetting
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Sets the default sharing level for OneDrive and Sharepoint. This is a tenant wide setting and overrules any settings set on the site level
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
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




