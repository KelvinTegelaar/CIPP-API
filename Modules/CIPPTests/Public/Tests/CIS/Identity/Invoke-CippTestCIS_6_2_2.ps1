function Invoke-CippTestCIS_6_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.2.2) - Mail transport rules SHALL NOT whitelist specific domains
    #>
    param($Tenant)

    try {
        $Rules = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoTransportRules'

        if (-not $Rules) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoTransportRules cache not found.' -Risk 'High' -Name 'Mail transport rules do not whitelist specific domains' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Whitelisting = $Rules | Where-Object {
            $_.State -eq 'Enabled' -and (
                $_.SetSCL -eq -1 -or
                ($_.SetHeaderName -eq 'X-Forefront-Antispam-Report' -and $_.SetHeaderValue -match 'IPV:CAL') -or
                ($_.SetHeaderName -eq 'X-MS-Exchange-Organization-BypassClutter') -or
                $_.SetSpamConfidenceLevel -eq -1
            )
        }

        if (-not $Whitelisting -or $Whitelisting.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No enabled transport rule whitelists senders by setting SCL to -1.'
        } else {
            $Status = 'Failed'
            $Result = "$($Whitelisting.Count) transport rule(s) whitelist senders by SCL=-1:`n`n"
            $Result += ($Whitelisting | Select-Object -First 25 | ForEach-Object { "- $($_.Name)" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Mail transport rules do not whitelist specific domains' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Mail transport rules do not whitelist specific domains' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
