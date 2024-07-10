function Invoke-CIPPStandardSPAzureB2B {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPAzureB2B
    .SYNOPSIS
        Enable SharePoint and OneDrive integration with Azure AD B2B
    .DESCRIPTION
        (Helptext) Ensure SharePoint and OneDrive integration with Azure AD B2B is enabled
        (DocsDescription) Ensure SharePoint and OneDrive integration with Azure AD B2B is enabled
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "lowimpact"
            "CIS"
        ADDEDCOMPONENT
        LABEL
            Enable SharePoint and OneDrive integration with Azure AD B2B
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -EnableAzureADB2BIntegration $true
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>

    param($Tenant, $Settings)
    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property EnableAzureADB2BIntegration

    $StateIsCorrect = ($CurrentState.EnableAzureADB2BIntegration -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Azure B2B is already enabled' -Sev Info
        } else {
            $Properties = @{
                EnableAzureADB2BIntegration = $true
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Message 'Successfully set the SharePoint Azure B2B to enabled' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Message "Failed to set the SharePoint Azure B2B to enabled. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Azure B2B is enabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Message 'SharePoint Azure B2B is not enabled' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AzureB2B' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
