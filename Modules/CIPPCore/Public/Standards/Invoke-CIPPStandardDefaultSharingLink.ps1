function Invoke-CIPPStandardDefaultSharingLink {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefaultSharingLink
    .SYNOPSIS
        (Label) Set Default Sharing Link Settings
    .DESCRIPTION
        (Helptext) Sets the default sharing link type to Internal and permission to View in SharePoint and OneDrive.
        (DocsDescription) Sets the default sharing link type to Internal and permission to View in SharePoint and OneDrive.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-13
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DefaultSharingLinkType Internal -DefaultLinkPermission View
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property DefaultSharingLinkType, DefaultLinkPermission

    $StateIsCorrect = ($CurrentState.DefaultSharingLinkType -eq 2) -and ($CurrentState.DefaultLinkPermission -eq 1)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Default sharing link settings are already configured correctly' -Sev Info
        } else {
            $Properties = @{
                DefaultSharingLinkType = 2  # Internal
                DefaultLinkPermission  = 1  # View
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set default sharing link settings' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set default sharing link settings. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Default sharing link settings are configured correctly' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Default sharing link settings are not configured correctly' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DefaultSharingLink' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.DefaultSharingLink' -FieldValue $FieldValue -Tenant $Tenant
    }
}
