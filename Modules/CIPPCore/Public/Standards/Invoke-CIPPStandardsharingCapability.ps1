function Invoke-CIPPStandardsharingCapability {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) sharingCapability
    .SYNOPSIS
        (Label) Set Sharing Level for OneDrive and SharePoint
    .DESCRIPTION
        (Helptext) Sets the default sharing level for OneDrive and SharePoint. This is a tenant wide setting and overrules any settings set on the site level
        (DocsDescription) Sets the default sharing level for OneDrive and SharePoint. This is a tenant wide setting and overrules any settings set on the site level
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select Sharing Level","name":"standards.sharingCapability.Level","options":[{"label":"Users can share only with people in the organization. No external sharing is allowed.","value":"disabled"},{"label":"Users can share with new and existing guests. Guests must sign in or provide a verification code.","value":"externalUserSharingOnly"},{"label":"Users can share with anyone by using links that do not require sign-in.","value":"externalUserAndGuestSharing"},{"label":"Users can share with existing guests (those already in the directory of the organization).","value":"existingExternalUserSharingOnly"}]}
        IMPACT
            High Impact
        ADDEDDATE
            2022-06-15
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminSharePointSetting
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#high-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'sharingCapability'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'sharingCapability' -FieldValue $CurrentInfo.sharingCapability -StoreAs string -Tenant $Tenant
    }

    # Get level value using null-coalescing operator
    $level = $Settings.Level.value ?? $Settings.Level

    # Input validation
    if (([string]::IsNullOrWhiteSpace($level) -or $level -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'sharingCapability: Invalid sharingCapability parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.sharingCapability -eq $level) {
            Write-Host "Sharing level is already set to $level"
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sharing level is already set to $level" -sev Info
        } else {
            Write-Host "Setting sharing level to $level from $($CurrentInfo.sharingCapability)"
            try {
                $body = @{
                    sharingCapability = $level
                }
                $bodyJson = ConvertTo-Json -InputObject $body -Compress
                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $bodyJson -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set sharing level to $level from $($CurrentInfo.sharingCapability)" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set sharing level to $level : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.sharingCapability -eq $level) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sharing level is set to $level" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sharing level is not set to $level" -sev Alert
        }
    }
}
