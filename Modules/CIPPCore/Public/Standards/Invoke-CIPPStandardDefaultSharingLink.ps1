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
        Select-Object -Property _ObjectIdentity_, TenantFilter, DefaultSharingLinkType, DefaultLinkPermission

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
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set default sharing link settings' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set default sharing link settings. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Default sharing link settings are configured correctly' -Sev Info
        } else {
            $Message = 'Default sharing link settings are not configured correctly'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'DefaultSharingLink' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
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
