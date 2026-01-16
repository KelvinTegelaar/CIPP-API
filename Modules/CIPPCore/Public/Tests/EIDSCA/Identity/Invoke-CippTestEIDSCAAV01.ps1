function Invoke-CippTestEIDSCAAV01 {
    <#
    .SYNOPSIS
    Voice Call - Disabled
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAV01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Voice Call - Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $VoiceConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Voice' }

        if (-not $VoiceConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAV01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Voice authentication configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'Voice Call - Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        if ($VoiceConfig.state -eq 'disabled') {
            $Status = 'Passed'
            $Result = 'Voice call authentication is disabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Voice call authentication should be disabled as it is susceptible to social engineering and SIM swap attacks.

**Current Configuration:**
- State: $($VoiceConfig.state)

**Recommended Configuration:**
- State: disabled

Disabling voice calls reduces the attack surface by eliminating a less secure authentication method.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAV01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Voice Call - Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAV01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Voice Call - Disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
