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

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property DefaultSharingLinkType

    $StateIsCorrect = ($CurrentState.DefaultSharingLinkType -eq 'Direct' -or $CurrentState.DefaultSharingLinkType -eq 1)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Sharing Restriction is already enabled' -Sev Info
        } else {
            $Properties = @{
                DefaultSharingLinkType = 1
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set the SharePoint Sharing Restriction to Direct' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the SharePoint Sharing Restriction to Direct. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Sharing Restriction is enabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Sharing Restriction is not enabled' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DirectSharing' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPDirectSharing' -FieldValue $FieldValue -Tenant $Tenant
    }
}
