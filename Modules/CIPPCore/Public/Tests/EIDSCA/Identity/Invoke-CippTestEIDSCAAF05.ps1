function Invoke-CippTestEIDSCAAF05 {
    <#
    .SYNOPSIS
    FIDO2 - Restricted Keys
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF05' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'FIDO2 - Restricted Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF05' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'FIDO2 - Restricted Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $aaGuids = $Fido2Config.keyRestrictions.aaGuids
        if ($aaGuids -and $aaGuids.Count -gt 0) {
            $Status = 'Passed'
            $Result = "FIDO2 key restrictions have specific AAGuids configured ($($aaGuids.Count) GUIDs)"
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 key restrictions should specify AAGuids to control which authenticator models can be registered.

**Current Configuration:**
- keyRestrictions.aaGuids: Empty or not configured

**Recommended Configuration:**
- keyRestrictions.aaGuids: Should contain one or more AAGuids

Specifying AAGuids allows you to restrict registration to specific, approved security key models.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF05' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'FIDO2 - Restricted Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF05' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'FIDO2 - Restricted Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    }
}
