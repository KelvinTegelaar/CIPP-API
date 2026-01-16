function Invoke-CippTestEIDSCAAT02 {
    <#
    .SYNOPSIS
    Temp Access Pass - One-Time
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Temp Access Pass - One-Time' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $TAPConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'TemporaryAccessPass' }

        if (-not $TAPConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Temporary Access Pass configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'Temp Access Pass - One-Time' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        if ($TAPConfig.isUsableOnce -eq $true) {
            $Status = 'Passed'
            $Result = 'Temporary Access Pass is configured for one-time use'
        } else {
            $Status = 'Failed'
            $Result = @"
Temporary Access Pass should be configured for one-time use to minimize security risks.

**Current Configuration:**
- isUsableOnce: $($TAPConfig.isUsableOnce)

**Recommended Configuration:**
- isUsableOnce: true

One-time use reduces the risk of TAP credential theft or misuse.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Temp Access Pass - One-Time' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Temp Access Pass - One-Time' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
