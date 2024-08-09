function Invoke-CIPPStandardSPAzureB2B {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPAzureB2B
    .SYNOPSIS
        (Label) Enable SharePoint and OneDrive integration with Azure AD B2B
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
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -EnableAzureADB2BIntegration \$true
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SPAzureB2B'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
    Select-Object -Property EnableAzureADB2BIntegration

    $StateIsCorrect = ($CurrentState.EnableAzureADB2BIntegration -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Azure B2B is already enabled' -Sev Info
        } else {
            $Properties = @{
                EnableAzureADB2BIntegration = $true
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set the SharePoint Azure B2B to enabled' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the SharePoint Azure B2B to enabled. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Azure B2B is enabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Azure B2B is not enabled' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AzureB2B' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
