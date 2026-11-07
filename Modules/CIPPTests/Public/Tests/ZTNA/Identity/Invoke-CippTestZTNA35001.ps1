function Invoke-CippTestZTNA35001 {
    <#
    .SYNOPSIS
    Conditional Access policies don't exclude Rights Management workloads
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35001'; TestType = 'Identity'; Name = "Conditional Access policies don't exclude Rights Management workloads"; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Entra' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35001' -TenantFilter $Tenant -RequiredCapabilities @('RMS_S_PREMIUM2') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection P2. Required capability: RMS_S_PREMIUM2.'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $Policies -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ConditionalAccessPolicies' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $RmsAppId = '00000012-0000-0000-c000-000000000000'
        $BlockingPolicies = @($Policies.Where({
                    $Included = $_.conditions.applications.includeApplications
                    $_.state -eq 'enabled' -and ($Included -contains 'All' -or $Included -contains $RmsAppId) -and $_.conditions.applications.excludeApplications -notcontains $RmsAppId
                }))

        if ($BlockingPolicies.Count -eq 0) {
            Add-CippTestResult @TestParams -Status 'Passed' -ResultMarkdown '✅ Microsoft Rights Management Service (RMS) is excluded from Conditional Access policies that enforce authentication controls.'
            return
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        $Lines.Add("❌ Microsoft Rights Management Service (RMS) is blocked or restricted by one or more Conditional Access policies.`n")
        $Lines.Add("**Policies Affecting RMS:**`n")
        $Lines.Add('| Policy Name | State | RMS Targeted | RMS Excluded | Grant Controls | Session Controls |')
        $Lines.Add('| :--- | :--- | :--- | :--- | :--- | :--- |')
        foreach ($Policy in $BlockingPolicies) {
            $Grant = @(
                $Policy.grantControls.builtInControls
                if ($Policy.grantControls.termsOfUse) { 'Terms of Use' }
            ).Where({ $_ })
            $Session = foreach ($Control in $Policy.sessionControls.PSObject.Properties) {
                $Value = $Control.Value
                $IsSet = if ($null -eq $Value) { $false } elseif ($Value -is [bool]) { $Value } elseif ($Value.PSObject.Properties['isEnabled']) { $Value.isEnabled } else { $true }
                if ($IsSet) {
                    $Words = $Control.Name -creplace '([a-z])([A-Z])', '$1 $2'
                    $Words.Substring(0, 1).ToUpper() + $Words.Substring(1)
                }
            }
            $GrantText = if ($Grant.Count) { $Grant -join ', ' } else { 'None' }
            $SessionText = if ($Session) { @($Session) -join ', ' } else { 'None' }
            $Lines.Add("| [$($Policy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)) | $($Policy.state) | Yes | No | $GrantText | $SessionText |")
        }

        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
