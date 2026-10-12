function Invoke-CIPPBaselineIntuneDeviceRetirementDays {
    <#
    .SYNOPSIS
        intuneDeviceRetirementDays executor: creates or patches the default device cleanup
        rule.
    .DESCRIPTION
        PATCH when the hook found a rule, POST when the tenant has none - the classic's
        exact branch, including its fixed 'Default Policy' rule body.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Body = ConvertTo-Json -Compress -InputObject ([PSCustomObject]@{
            displayName                            = 'Default Policy'
            description                            = 'Default Policy'
            deviceCleanupRulePlatformType          = 'all'
            deviceInactivityBeforeRetirementInDays = [int]"$($Remediate.days)"
        })
    # Tenants with Intune multi-admin approval on device clean-up rules reject the write
    # outright unless a justification header rides along; with it, the write either applies
    # or lands as an approval request for another admin to action.
    $Headers = @{ 'x-msft-approval-justification' = 'CIPP baseline remediation: enforce the configured device retirement window.' }
    if ($Current.ruleId) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupRules('$($Current.ruleId)')" -type PATCH -body $Body -AddedHeaders $Headers
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set device retirement to $($Remediate.days) days on the existing cleanup rule." -Sev 'Info'
    } else {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupRules' -type POST -body $Body -AddedHeaders $Headers
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created the default device cleanup rule at $($Remediate.days) days." -Sev 'Info'
    }
}
