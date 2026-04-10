function Invoke-CippTestGenericTest003 {
    <#
    .SYNOPSIS
    License Renewal Report — upcoming renewal dates, terms, and trial status
    #>
    param($Tenant)

    try {
        $LicenseData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest003' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in the reporting database. Please sync the License Overview cache first.' -Risk 'Informational' -Name 'License Renewal Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Licenses = @($LicenseData)

        $Result = ""

        $HasRenewals = $false
        $TrialCount = 0
        $UpcomingRenewals = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($License in $Licenses) {
            $TermInfo = if ($License.TermInfo -is [string]) {
                try { $License.TermInfo | ConvertFrom-Json } catch { @() }
            } else { $License.TermInfo }

            if (-not $TermInfo) { continue }

            foreach ($Term in $TermInfo) {
                $HasRenewals = $true
                if ($Term.IsTrial -eq $true) { $TrialCount++ }
                $UpcomingRenewals.Add([PSCustomObject]@{
                    License        = $License.License
                    Status         = $Term.Status
                    Term           = $Term.Term
                    Seats          = $Term.TotalLicenses
                    DaysUntilRenew = $Term.DaysUntilRenew
                    NextRenewal    = if ($Term.NextLifecycle) { ([datetime]$Term.NextLifecycle).ToString('yyyy-MM-dd') } else { 'Unknown' }
                    IsTrial        = $Term.IsTrial
                })
            }
        }

        if (-not $HasRenewals) {
            $Result += 'No subscription renewal information is available. This may indicate non-standard licensing or the data has not been synced recently.'
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest003' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'License Renewal Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        if ($TrialCount -gt 0) {
            $Result += "**⚠️ $TrialCount trial subscription(s) detected.** Trial licenses will expire and may cause users to lose access if not converted to paid subscriptions.`n`n"
        }

        $UrgentRenewals = @($UpcomingRenewals | Where-Object { $_.DaysUntilRenew -le 30 -and $_.DaysUntilRenew -ge 0 })
        if ($UrgentRenewals.Count -gt 0) {
            $Result += "**🔴 $($UrgentRenewals.Count) subscription(s) renewing within 30 days** — review these to ensure billing and seat counts are correct.`n`n"
        }

        $Sorted = $UpcomingRenewals | Sort-Object DaysUntilRenew

        $Result += "| License | Status | Billing Term | Seats | Renews In | Renewal Date | Trial |`n"
        $Result += "|---------|--------|--------------|-------|-----------|--------------|-------|`n"

        foreach ($Renewal in $Sorted) {
            $DaysLabel = if ($null -eq $Renewal.DaysUntilRenew) { 'Unknown' }
            elseif ($Renewal.DaysUntilRenew -lt 0) { 'Past due' }
            elseif ($Renewal.DaysUntilRenew -eq 0) { 'Today' }
            else { "$($Renewal.DaysUntilRenew) days" }
            $TrialLabel = if ($Renewal.IsTrial -eq $true) { '⚠️ Yes' } else { 'No' }
            $StatusIcon = switch ($Renewal.Status) {
                'Enabled' { "✅ $($Renewal.Status)" }
                'Warning' { "⚠️ $($Renewal.Status)" }
                'Suspended' { "🔴 $($Renewal.Status)" }
                'Deleted' { "❌ $($Renewal.Status)" }
                default { $Renewal.Status }
            }
            $Result += "| $($Renewal.License) | $StatusIcon | $($Renewal.Term) | $($Renewal.Seats) | $DaysLabel | $($Renewal.NextRenewal) | $TrialLabel |`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest003' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'License Renewal Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest003: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest003' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'License Renewal Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
