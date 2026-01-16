function Invoke-CippTestORCA233_1 {
    <#
    .SYNOPSIS
    Enhanced filtering on default connectors
    #>
    param($Tenant)

    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No organization config found in database.' -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Configuration'
            return
        }

        $Config = $OrgConfig | Select-Object -First 1

        # Check if enhanced filtering is enabled
        # This property may vary depending on Exchange Online version
        $EnhancedFilteringEnabled = $false

        # Check various properties that indicate enhanced filtering
        if ($Config.PSObject.Properties.Name -contains 'SkipListedFromForging') {
            $EnhancedFilteringEnabled = $Config.SkipListedFromForging -eq $false
        }

        if ($EnhancedFilteringEnabled) {
            $Status = 'Passed'
            $Result = "Enhanced filtering appears to be properly configured.`n`n"
            $Result += "**Configuration:** Reviewed"
        } else {
            $Status = 'Informational'
            $Result = "Unable to fully determine enhanced filtering status. Manual review recommended.`n`n"
            $Result += "**Action Required:** Review inbound connectors for enhanced filtering configuration"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Enhanced filtering on default connectors' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Configuration'
    }
}
