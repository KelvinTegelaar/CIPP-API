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
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -EnableAzureADB2BIntegration \$true
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPAzureB2B' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property _ObjectIdentity_, TenantFilter, EnableAzureADB2BIntegration

    $StateIsCorrect = ($CurrentState.EnableAzureADB2BIntegration -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Azure B2B is already enabled' -Sev Info
        } else {
            $Properties = @{
                EnableAzureADB2BIntegration = $true
            }

            try {
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
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
            $Message = 'SharePoint Azure B2B is not enabled.'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPAzureB2B' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AzureB2B' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPAzureB2B' -FieldValue $FieldValue -Tenant $Tenant
    }
}
