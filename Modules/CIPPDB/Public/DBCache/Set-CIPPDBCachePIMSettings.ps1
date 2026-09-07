function Set-CIPPDBCachePIMSettings {
    <#
    .SYNOPSIS
        Caches PIM (Privileged Identity Management) settings for a tenant (if CA capable)

    .PARAMETER TenantFilter
        The tenant to cache PIM settings for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'PIMSettingsCache' -TenantFilter $TenantFilter -Preset EntraP2 -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Azure AD Premium P2 license, skipping PIM' -sev Debug
            # A license skip is still a completed collection: record authoritative empty sets for
            # both types this collector writes so collect-on-miss does not re-run it forever.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMRoleSettings' -Data @() -AddCount -ClearOnEmpty
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMAssignments' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching PIM settings' -sev Debug

        try {
            $PIMRoleSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/roleManagementPolicyAssignments?$top=999' -tenantid $TenantFilter

            if ($PIMRoleSettings) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMRoleSettings' -Data $PIMRoleSettings -AddCount
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($PIMRoleSettings.Count) PIM role settings" -sev Debug
            } else {
                # The request succeeded with nothing returned: write the authoritative empty set so the
                # Count marker records a completed collection and stale rows are cleared.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMRoleSettings' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 PIM role settings (none found)' -sev Debug
            }
            $PIMRoleSettings = $null
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache PIM role settings: $($_.Exception.Message)" -sev Warning
        }

        try {
            $PIMAssignments = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilityScheduleInstances?$top=999' -tenantid $TenantFilter

            if ($PIMAssignments) {
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMAssignments' -Data $PIMAssignments -AddCount
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($PIMAssignments.Count) PIM assignments" -sev Debug
            } else {
                # The request succeeded with nothing returned: write the authoritative empty set so the
                # Count marker records a completed collection and stale rows are cleared.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMAssignments' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 PIM assignments (none found)' -sev Debug
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
