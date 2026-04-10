function Invoke-CippTestGenericTest002 {
    <#
    .SYNOPSIS
    User License Overview — which users have which licenses assigned
    #>
    param($Tenant)

    try {
        $LicenseData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest002' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in the reporting database. Please sync the License Overview cache first.' -Risk 'Informational' -Name 'User License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Licenses = @($LicenseData)

        # Build a map of user -> licenses
        $UserLicenseMap = @{}
        foreach ($License in $Licenses) {
            if (-not $License.AssignedUsers) { continue }
            $AssignedUsers = if ($License.AssignedUsers -is [string]) {
                try { $License.AssignedUsers | ConvertFrom-Json } catch { @() }
            } else { $License.AssignedUsers }

            foreach ($User in $AssignedUsers) {
                $UPN = $User.userPrincipalName
                if (-not $UPN) { continue }
                if (-not $UserLicenseMap.ContainsKey($UPN)) {
                    $UserLicenseMap[$UPN] = @{
                        DisplayName = $User.displayName
                        Licenses    = [System.Collections.Generic.List[string]]::new()
                    }
                }
                $UserLicenseMap[$UPN].Licenses.Add($License.License)
            }
        }

        if ($UserLicenseMap.Count -eq 0) {
            $Result = "No users with assigned licenses were found in the cached data.`n`nThis may indicate that the license data has not been synced recently, or no licenses have been assigned to individual users."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest002' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Result = "**Total Licensed Users:** $($UserLicenseMap.Count)`n`n"

        $Result += "| User | Licenses |`n"
        $Result += "|------|----------|`n"

        $SortedUsers = $UserLicenseMap.GetEnumerator() | Sort-Object { $_.Value.DisplayName }
        $DisplayCount = 0
        foreach ($Entry in $SortedUsers) {
            $DisplayName = $Entry.Value.DisplayName
            $LicList = ($Entry.Value.Licenses | Sort-Object) -join ', '
            $Result += "| $DisplayName | $LicList |`n"
            $DisplayCount++
            if ($DisplayCount -ge 100) { break }
        }

        if ($UserLicenseMap.Count -gt 100) {
            $Result += "`n*Showing 100 of $($UserLicenseMap.Count) licensed users.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest002' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest002: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest002' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'User License Overview' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
