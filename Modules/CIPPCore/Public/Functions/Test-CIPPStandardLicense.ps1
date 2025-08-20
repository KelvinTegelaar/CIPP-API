function Test-CIPPStandardLicense {
    <#
    .SYNOPSIS
        Tests if a tenant has the required license capabilities for a specific standard
    .DESCRIPTION
        This function checks if a tenant has the necessary license capabilities to run a specific standard.
        If the license is missing, it logs an error and sets the comparison field appropriately.
    .PARAMETER StandardName
        The name of the standard to check licensing for
    .PARAMETER TenantFilter
        The tenant to check licensing for
    .PARAMETER RequiredCapabilities
        Array of required capabilities for the standard
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Test-CIPPStandardLicense -StandardName "ConditionalAccessTemplate" -TenantFilter "contoso.onmicrosoft.com" -RequiredCapabilities @('AADPremiumService')
    .EXAMPLE
        Test-CIPPStandardLicense -StandardName "SafeLinksPolicy" -TenantFilter "contoso.onmicrosoft.com" -RequiredCapabilities @('DEFENDER_FOR_OFFICE_365_PLAN_1', 'DEFENDER_FOR_OFFICE_365_PLAN_2')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StandardName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredCapabilities,

        [Parameter(Mandatory = $false)]
        [switch]$SkipLog
    )

    try {
        $TenantCapabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter

        $Capabilities = foreach ($Capability in $RequiredCapabilities) {
            Write-Host "Checking capability: $Capability"
            if ($TenantCapabilities.$Capability -eq $true) {
                $Capability
            }
        }

        if ($Capabilities.Count -le 0) {
            if (!$SkipLog.IsPresent) {
                Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "Tenant does not have the required capability to run standard $StandardName`: The tenant needs one of the following service plans: $($RequiredCapabilities -join ',')" -sev Error
                Set-CIPPStandardsCompareField -FieldName "standards.$StandardName" -FieldValue "License Missing: This tenant is not licensed for the following capabilities: $($RequiredCapabilities -join ',')" -Tenant $TenantFilter
                Write-Host "Tenant does not have the required capability to run standard $StandardName - $($RequiredCapabilities -join ','). Exiting"
            }
            return $false
        }
        Write-Host "Tenant has the required capabilities for standard $StandardName"
        return $true
    } catch {
        if (!$SkipLog.IsPresent) {
            Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "Error checking license capabilities for standard $StandardName`: $($_.Exception.Message)" -sev Error
            Set-CIPPStandardsCompareField -FieldName "standards.$StandardName" -FieldValue "License Missing: Error checking license capabilities - $($_.Exception.Message)" -Tenant $TenantFilter
        }
        return $false
    }
}
