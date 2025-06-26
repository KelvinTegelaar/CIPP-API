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
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DefaultSharingLinkType Direct
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'This standard has been deprecated in favor of the Set Default Sharing Link Settings standard. Please update your standards to use new standard.' -Sev Alert
}
