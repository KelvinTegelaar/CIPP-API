function Set-CIPPDBCachePIMSettings {
    <#
    .SYNOPSIS
        Caches PIM (Privileged Identity Management) settings for a tenant (if CA capable)

    .PARAMETER TenantFilter
        The tenant to cache PIM settings for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'PIMSettingsCache' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Azure AD Premium P2 license, skipping PIM' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching PIM settings' -sev Debug

        try {
            $PIMRoleSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/roleManagementPolicyAssignments?$top=999' -tenantid $TenantFilter

            if ($PIMRoleSettings) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMRoleSettings' -Data $PIMRoleSettings
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMRoleSettings' -Data $PIMRoleSettings -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($PIMRoleSettings.Count) PIM role settings" -sev Debug
            }
            $PIMRoleSettings = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache PIM role settings: $($_.Exception.Message)" -sev Warning
        }

        try {
            $PIMAssignments = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilityScheduleInstances?$top=999' -tenantid $TenantFilter

            if ($PIMAssignments) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMAssignments' -Data $PIMAssignments
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMAssignments' -Data $PIMAssignments -Count
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($PIMAssignments.Count) PIM assignments" -sev Debug
            }
            $PIMAssignments = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache PIM assignments: $($_.Exception.Message)" -sev Warning
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached PIM settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache PIM settings: $($_.Exception.Message)" -sev Error
    }
}
