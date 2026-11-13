function Get-CIPPStatsLicenseTotals {
    <#
    .SYNOPSIS
    Purchased license totals per product name across every tenant, for the anonymous stats payload

    .DESCRIPTION
    Reads the cached LicenseOverview rows (Get-CIPPLicenseOverview output, excluded SKUs already
    removed) and sums TotalLicenses per pretty name.
    #>
    [CmdletBinding()]
    param()

    try {
        $Totals = @{}
        $Rows = Get-CIPPDbItem -TenantFilter allTenants -Type 'LicenseOverview' -ByTenant
        foreach ($Tenant in $Rows.Keys) {
            foreach ($Row in $Rows[$Tenant]) {
                if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
                $Parsed = try { [CIPP.CippJson]::ConvertFromJson([string]$Row.Data, [string[]]@('License', 'TotalLicenses')) } catch { $null }
                foreach ($License in @($Parsed)) {
                    $Name = [string]$License.License
                    if ([string]::IsNullOrWhiteSpace($Name)) { continue }
                    $Count = 0
                    if (-not [int]::TryParse([string]$License.TotalLicenses, [ref]$Count)) { continue }
                    $Totals[$Name] = [int]($Totals[$Name] ?? 0) + $Count
                }
            }
        }

        $Sorted = [ordered]@{}
        foreach ($Name in ($Totals.Keys | Sort-Object)) { $Sorted[$Name] = $Totals[$Name] }
        return $Sorted
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate license totals: $($_.Exception.Message)" -sev Warning
        return [ordered]@{}
    }
}
