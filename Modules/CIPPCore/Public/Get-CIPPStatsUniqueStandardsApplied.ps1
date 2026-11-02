function Get-CIPPStatsUniqueStandardsApplied {
    [CmdletBinding()]
    param()

    try {
        $Standards = @(Get-CIPPStandards -TenantFilter allTenants)
        $DistinctStandards = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($Standard in $Standards) {
            if (-not $Standard.Standard) { continue }

            $TemplateValue = $null
            if ($Standard.Settings -and $Standard.Settings.PSObject.Properties['TemplateList']) {
                if ($Standard.Settings.TemplateList -and $Standard.Settings.TemplateList.PSObject.Properties['value']) {
                    $TemplateValue = [string]$Standard.Settings.TemplateList.value
                }
            }

            $Id = if ([string]::IsNullOrWhiteSpace($TemplateValue)) {
                [string]$Standard.Standard
            } else {
                '{0}|{1}' -f $Standard.Standard, $TemplateValue
            }

            if ([string]::IsNullOrWhiteSpace($Id)) { continue }
            [void]$DistinctStandards.Add($Id)
        }

        return $DistinctStandards.Count
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate UniqueStandardsApplied: $($_.Exception.Message)" -sev Warning
        return 0
    }
}
