function Invoke-CippTestEIDSCAAF06 {
    <#
    .SYNOPSIS
    FIDO2 - Specific Keys
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF06' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'FIDO2 - Specific Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF06' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'FIDO2 - Specific Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $aaGuids = $Fido2Config.keyRestrictions.aaGuids
        $enforcementType = $Fido2Config.keyRestrictions.enforcementType

        if ($aaGuids -and $aaGuids.Count -gt 0 -and $enforcementType -in @('allow', 'block')) {
            $Status = 'Passed'
            $Result = "FIDO2 key restrictions are properly configured with enforcement type '$enforcementType' and $($aaGuids.Count) AAGuids"
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 key restrictions should have both AAGuids configured and a valid enforcement type (allow or block).

**Current Configuration:**
- keyRestrictions.aaGuids: $($aaGuids.Count) GUIDs configured
- keyRestrictions.enforcementType: $enforcementType

**Recommended Configuration:**
- keyRestrictions.aaGuids: One or more AAGuids
- keyRestrictions.enforcementType: 'allow' or 'block'

Proper enforcement type ensures the AAGuids list is actively used to control key registration.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF06' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'FIDO2 - Specific Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF06' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'FIDO2 - Specific Keys' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    }
}
