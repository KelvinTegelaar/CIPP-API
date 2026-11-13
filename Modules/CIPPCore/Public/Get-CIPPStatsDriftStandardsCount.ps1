function Get-CIPPStatsDriftStandardsCount {
    [CmdletBinding()]
    param(
        # Get-CIPPStandards -TenantFilter allTenants, read once by the caller
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Standards
    )

    try {
        $TemplateTable = Get-CippTable -tablename 'templates'
        $TemplateRows = @(Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'StandardsTemplateV2'")

        $TemplateTypeByGuid = @{}
        foreach ($TemplateRow in $TemplateRows) {
            if (-not $TemplateRow.JSON) { continue }

            $TemplateData = try { [CIPP.CippJson]::ConvertFromJson([string]$TemplateRow.JSON, [string[]]@('GUID', 'type')) } catch { continue }

            $TemplateGuid = [string]($TemplateData.GUID ?? $TemplateRow.GUID)
            if ([string]::IsNullOrWhiteSpace($TemplateGuid)) { continue }

            $TemplateTypeByGuid[$TemplateGuid] = [string]$TemplateData.type
        }

        $DriftStandardIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Standard in $Standards) {
            if ([string]::IsNullOrWhiteSpace($Standard.TemplateId)) { continue }
            if ([string]::IsNullOrWhiteSpace($Standard.Standard)) { continue }
            if (-not $TemplateTypeByGuid.ContainsKey([string]$Standard.TemplateId)) { continue }
            if ($TemplateTypeByGuid[[string]$Standard.TemplateId] -ne 'drift') { continue }

            $TemplateValue = $null
            if ($Standard.Settings -and $Standard.Settings.PSObject.Properties['TemplateList']) {
                if ($Standard.Settings.TemplateList -and $Standard.Settings.TemplateList.PSObject.Properties['value']) {
                    $TemplateValue = [string]$Standard.Settings.TemplateList.value
                }
            }

            $Id = if ([string]::IsNullOrWhiteSpace($TemplateValue)) {
                [string]$Standard.Standard
            } else {
                "{0}|{1}" -f $Standard.Standard, $TemplateValue
            }

            if ([string]::IsNullOrWhiteSpace($Id)) { continue }
            [void]$DriftStandardIds.Add($Id)
        }

        return $DriftStandardIds.Count
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate DriftStandardsCount: $($_.Exception.Message)" -sev Warning
        return 0
    }
}
