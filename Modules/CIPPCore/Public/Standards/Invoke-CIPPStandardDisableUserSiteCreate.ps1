function Invoke-CIPPStandardDisableUserSiteCreate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableUserSiteCreate
    .SYNOPSIS
        (Label) Disable site creation by standard users
    .DESCRIPTION
        (Helptext) Disables users from creating new SharePoint sites
        (DocsDescription) Disables standard users from creating SharePoint sites, also disables the ability to fully create teams
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "highimpact"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Update-MgAdminSharepointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableUserSiteCreate'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.isSiteCreationEnabled) {
            try {
                $body = '{"isSiteCreationEnabled": false}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled standard users from creating sites' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable standard users from creating sites: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standard users are already disabled from creating sites' -sev Info
        }

    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isSiteCreationEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standard users are not allowed to create sites' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standard users are allowed to create sites' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableUserSiteCreate' -FieldValue $CurrentInfo.isSiteCreationEnabled -StoreAs bool -Tenant $tenant
    }
}
