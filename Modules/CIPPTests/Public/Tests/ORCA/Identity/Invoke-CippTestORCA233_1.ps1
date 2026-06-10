function Invoke-CippTestORCA233_1 {
    <#
    .SYNOPSIS
    Enhanced filtering on default connectors
    #>
    param($Tenant)

    try {
        $Connectors = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoInboundConnector'

        if (-not $Connectors) {
            # No connectors at all means no third-party mail flow path to misconfigure.
            $Result = [System.Text.StringBuilder]::new("No inbound connectors are configured. Enhanced filtering is not required.")
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status 'Passed' -ResultMarkdown $Result -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Connectors'
            return
        }

        # Find enabled connectors with wildcard sender domain ('smtp:*;N' priority pattern).
        # These are the third-party mail flow connectors that need enhanced filtering.
        $WildcardPattern = '^smtp:\*;(\d+)$'
        $RelevantConnectors = [System.Collections.Generic.List[object]]::new()
        foreach ($Connector in $Connectors) {
            if ($Connector.Enabled -ne $true) { continue }
            foreach ($SenderDomain in @($Connector.SenderDomains)) {
                if ($SenderDomain -match $WildcardPattern) {
                    $RelevantConnectors.Add($Connector) | Out-Null
                    break
                }
            }
        }

        if ($RelevantConnectors.Count -eq 0) {
            $Result = [System.Text.StringBuilder]::new("No enabled inbound connectors with wildcard sender domains were found. Enhanced filtering is not required.")
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status 'Passed' -ResultMarkdown $Result -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Connectors'
            return
        }

        $FailedConnectors = [System.Collections.Generic.List[object]]::new()
        $PassedConnectors = [System.Collections.Generic.List[object]]::new()

        foreach ($Connector in $RelevantConnectors) {
            $SkipLast = $Connector.EFSkipLastIP -eq $true
            $SkipIPsCount = @($Connector.EFSkipIPs).Count
            $TestMode = $Connector.EFTestMode -eq $true
            $UsersCount = @($Connector.EFUsers).Count

            $IsCompliant = ($SkipLast -or $SkipIPsCount -gt 0) -and -not $TestMode -and $UsersCount -eq 0

            $Mode = if ($SkipLast) { 'Last IP' }
            elseif ($SkipIPsCount -gt 0) { "Skip IPs ($SkipIPsCount)" }
            else { 'Not Configured' }
            if ($TestMode) { $Mode += ' (Test Mode)' }
            if ($UsersCount -gt 0) { $Mode += " (Select Users: $UsersCount)" }

            $Entry = [PSCustomObject]@{
                Identity = $Connector.Identity
                Mode     = $Mode
            }

            if ($IsCompliant) { $PassedConnectors.Add($Entry) | Out-Null }
            else { $FailedConnectors.Add($Entry) | Out-Null }
        }

        if ($FailedConnectors.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All inbound connectors with wildcard sender domains have enhanced filtering configured.`n`n")
            $null = $Result.Append("**Compliant Connectors:** $($PassedConnectors.Count)`n`n")
            $null = $Result.Append("| Connector | EF Mode |`n")
            $null = $Result.Append("|-----------|---------|`n")
            foreach ($Entry in $PassedConnectors) {
                $null = $Result.Append("| $($Entry.Identity) | $($Entry.Mode) |`n")
            }
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedConnectors.Count) inbound connectors do not have enhanced filtering configured correctly.`n`n")
            $null = $Result.Append("**Failed:** $($FailedConnectors.Count) | **Passed:** $($PassedConnectors.Count)`n`n")
            $null = $Result.Append("| Connector | EF Mode |`n")
            $null = $Result.Append("|-----------|---------|`n")
            foreach ($Entry in $FailedConnectors) {
                $null = $Result.Append("| $($Entry.Identity) | $($Entry.Mode) |`n")
            }
            $null = $Result.Append("`n**Remediation:** Enable enhanced filtering on each connector by setting `EFSkipLastIP = `$true` (or populating `EFSkipIPs`), with `EFTestMode = `$false` and no per-user scoping.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Connectors'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Connectors'
    }
}
