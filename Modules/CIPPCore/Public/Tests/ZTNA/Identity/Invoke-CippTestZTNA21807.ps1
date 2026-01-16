function Invoke-CippTestZTNA21807 {
    <#
    .SYNOPSIS
    Creating new applications and service principals is restricted to privileged users
    #>
    param($Tenant)
    #Tested
    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21807' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Creating new applications and service principals is restricted to privileged users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $CanCreateApps = $AuthPolicy.defaultUserRolePermissions.allowedToCreateApps

        if ($CanCreateApps -eq $false) {
            $Status = 'Passed'
            $Result = 'Tenant is configured to prevent users from registering applications'
        } else {
            $Status = 'Failed'
            $Result = 'Tenant allows all non-privileged users to register applications'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21807' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Creating new applications and service principals is restricted to privileged users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21807' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Creating new applications and service principals is restricted to privileged users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
