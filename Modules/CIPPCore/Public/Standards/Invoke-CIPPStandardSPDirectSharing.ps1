function Invoke-CIPPStandardSPDirectSharing {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDirectSharing
    .SYNOPSIS
        (Label) Default sharing to Direct users
    .DESCRIPTION
        (Helptext) Ensure default link sharing is set to Direct in SharePoint and OneDrive
        (DocsDescription) Ensure default link sharing is set to Direct in SharePoint and OneDrive
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "mediumimpact"
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DefaultSharingLinkType Direct
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property DefaultSharingLinkType

    $StateIsCorrect = ($CurrentState.DefaultSharingLinkType -eq 'Direct')

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Sharing Restriction is already enabled' -Sev Info
        } else {
            $Properties = @{
                DefaultSharingLinkType = 1
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Message 'Successfully set the SharePoint Sharing Restriction to Direct' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Message "Failed to set the SharePoint Sharing Restriction to Direct. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Sharing Restriction is enabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Sharing Restriction is not enabled' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DirectSharing' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
