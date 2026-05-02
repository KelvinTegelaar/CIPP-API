function Invoke-CIPPStandardSPDisableStoreAccess {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDisableStoreAccess
    .SYNOPSIS
        (Label) Disable SharePoint Store access
    .DESCRIPTION
        (Helptext) Disables end users from installing applications from the Microsoft Store into SharePoint sites.
        (DocsDescription) Removes the ability for end users to install applications directly from the Microsoft Store into SharePoint. This prevents uncontrolled app installations that can increase governance costs and go against organizational policies.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Prevents end users from installing applications from the Microsoft Store into SharePoint sites, ensuring that only approved applications are available. This reduces governance overhead and aligns with Microsoft's Baseline Security Mode recommendations.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-04-28
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisableSharePointStoreAccess $true
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPDisableStoreAccess' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
            Select-Object _ObjectIdentity_, TenantFilter, DisableSharePointStoreAccess
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPDisableStoreAccess state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($null -eq $CurrentState._ObjectIdentity_) {
        $ErrorDetail = $CurrentState.ErrorInfo ?? 'No tenant data returned from CSOM query'
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPDisableStoreAccess state for $Tenant. CSOM error: $ErrorDetail" -Sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.DisableSharePointStoreAccess -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Store access is already disabled.' -Sev Info
        } else {
            try {
                $CurrentState | Set-CIPPSPOTenant -Properties @{ DisableSharePointStoreAccess = $true }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully disabled SharePoint Store access.' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to disable SharePoint Store access. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Store access is disabled.' -Sev Info
        } else {
            Write-StandardsAlert -message 'SharePoint Store access is enabled.' -object $CurrentState -tenant $Tenant -standardName 'SPDisableStoreAccess' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Store access is enabled.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            SPDisableStoreAccess = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            SPDisableStoreAccess = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPDisableStoreAccess' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SPDisableStoreAccess' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
