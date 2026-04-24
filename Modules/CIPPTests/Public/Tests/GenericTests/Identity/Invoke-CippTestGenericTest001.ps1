function Invoke-CippTestGenericTest001 {
    <#
    .SYNOPSIS
    Tenant License Overview — informational summary of all licenses in the tenant
    #>
    param($Tenant)

    try {
        $LicenseData = Get-CIPPTestData -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest001' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in the reporting database. Please sync the License Overview cache first.' -Risk 'Informational' -Name 'Tenant License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Licenses = @($LicenseData)
        $TotalLicenses = ($Licenses | ForEach-Object { [int]$_.TotalLicenses } | Measure-Object -Sum).Sum
        $TotalUsed = ($Licenses | ForEach-Object { [int]$_.CountUsed } | Measure-Object -Sum).Sum
        $OverallUtilization = if ($TotalLicenses -gt 0) { [math]::Round(($TotalUsed / $TotalLicenses) * 100, 1) } else { 0 }

        $Result = "**Total Licenses:** $TotalLicenses | **In Use:** $TotalUsed | **Overall Utilization:** $OverallUtilization%`n`n"

        $Result += "| License | In Use | Total | Available | Utilization |`n"
        $Result += "|---------|--------|-------|-----------|-------------|`n"

        foreach ($License in ($Licenses | Sort-Object { [int]$_.TotalLicenses } -Descending)) {
            $LicName = $License.License
            $Used = [int]$License.CountUsed
            $Total = [int]$License.TotalLicenses
            $Available = $Total - $Used
            $Util = if ($Total -gt 0) { [math]::Round(($Used / $Total) * 100, 0) } else { 0 }
            $UtilIcon = if ($Util -ge 90) { "🟢 $Util%" } elseif ($Util -ge 70) { "🟡 $Util%" } else { "🟢 $Util%" }
            $Result += "| $LicName | $Used | $Total | $Available | $UtilIcon |`n"
        }


        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest001' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Tenant License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest001: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest001' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Tenant License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
