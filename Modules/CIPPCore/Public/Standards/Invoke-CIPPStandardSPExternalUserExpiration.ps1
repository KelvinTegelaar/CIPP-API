function Invoke-CIPPStandardSPExternalUserExpiration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPExternalUserExpiration
    .SYNOPSIS
        (Label) Set guest access to expire automatically
    .DESCRIPTION
        (Helptext) Ensure guest access to a site or OneDrive will expire automatically
        (DocsDescription) Ensure guest access to a site or OneDrive will expire automatically
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "mediumimpact"
            "CIS"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SPExternalUserExpiration.Days","label":"Days until expiration (Default 60)"}
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -ExternalUserExpireInDays 30 -ExternalUserExpirationRequired \$True
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SPExternalUserExpiration'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
    Select-Object -Property ExternalUserExpireInDays, ExternalUserExpirationRequired

    $StateIsCorrect = ($CurrentState.ExternalUserExpireInDays -eq $Settings.Days) -and
                      ($CurrentState.ExternalUserExpirationRequired -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Sharepoint External User Expiration is already enabled.' -Sev Info
        } else {
            $Properties = @{
                ExternalUserExpireInDays       = $Settings.Days
                ExternalUserExpirationRequired = $true
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set External User Expiration' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set External User Expiration. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'External User Expiration is enabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'External User Expiration is not enabled' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'ExternalUserExpiration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
