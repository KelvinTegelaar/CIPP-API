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
            "CIS M365 5.0 (7.2.3)"
            "CISA (MS.AAD.14.1v1)"
            "CISA (MS.SPO.1.1v1)"
        EXECUTIVETEXT
            Defines the organization's default policy for sharing files and folders in SharePoint and OneDrive, balancing collaboration needs with security requirements. This fundamental setting determines whether employees can share with external users, anonymous links, or only internal colleagues.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'sharingCapability' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the sharingCapability state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'sharingCapability' -FieldValue $CurrentInfo.sharingCapability -StoreAs string -Tenant $Tenant
    }

    # Get level value using null-coalescing operator
    $level = $Settings.Level.value ?? $Settings.Level

    # Input validation
    if (([string]::IsNullOrWhiteSpace($level) -or $level -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'sharingCapability: Invalid sharingCapability parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {

        if ($CurrentInfo.sharingCapability -eq $level) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sharing level is already set to $level" -sev Info
        } else {
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
            Write-StandardsAlert -message "Sharing level is not set to $level" -object $CurrentInfo -tenant $Tenant -standardName 'sharingCapability' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sharing level is not set to $level" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            sharingCapability = $CurrentInfo.sharingCapability
        }
        $ExpectedValue = @{
            sharingCapability = $level
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.sharingCapability' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
