function Get-CIPPAlertVulnerabilities {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $VulnerabilityRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine?`$top=999&`$filter=cveId ne null" -scope 'https://api.securitycenter.microsoft.com/.default'

        if ($VulnerabilityRequest) {
            $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Group by CVE ID and create objects for each vulnerability
            $VulnerabilityGroups = $VulnerabilityRequest | Where-Object { $_.cveId } | Group-Object cveId

            foreach ($Group in $VulnerabilityGroups) {
                $FirstVuln = $Group.Group | Sort-Object firstSeenTimestamp | Select-Object -First 1
                $HoursOld = [math]::Round(((Get-Date) - [datetime]$FirstVuln.firstSeenTimestamp).TotalHours)

                # Skip if vulnerability is not old enough
                if ($HoursOld -lt [int]$InputValue) {
                    continue
                }

                $DaysOld = [math]::Round(((Get-Date) - [datetime]$FirstVuln.firstSeenTimestamp).TotalDays)
                $AffectedDevices = ($Group.Group | Select-Object -ExpandProperty deviceName -Unique) -join ', '

                $VulnerabilityAlert = [PSCustomObject]@{
                    CVE                  = $Group.Name
                    Severity             = $FirstVuln.vulnerabilitySeverityLevel
                    FirstSeenTimestamp   = $FirstVuln.firstSeenTimestamp
                    LastSeenTimestamp    = $FirstVuln.lastSeenTimestamp
                    DaysOld              = $DaysOld
                    HoursOld             = $HoursOld
                    AffectedDeviceCount  = $Group.Count
                    AffectedDevices      = $AffectedDevices
                    SoftwareName         = $FirstVuln.softwareName
                    SoftwareVendor       = $FirstVuln.softwareVendor
                    SoftwareVersion      = $FirstVuln.softwareVersion
                    CVSSScore            = $FirstVuln.cvssScore
                    ExploitabilityLevel  = $FirstVuln.exploitabilityLevel
                    RecommendedUpdate    = $FirstVuln.recommendedSecurityUpdate
                    RecommendedUpdateId  = $FirstVuln.recommendedSecurityUpdateId
                    RecommendedUpdateUrl = $FirstVuln.recommendedSecurityUpdateUrl
                    Tenant               = $TenantFilter
                }
                $AlertData.Add($VulnerabilityAlert)
            }

            # Only send alert if we have vulnerabilities that meet the criteria
            if ($AlertData.Count -gt 0) {
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-LogMessage -message "Failed to check vulnerabilities: $($_.exception.message)" -API 'Vulnerability Alerts' -tenant $TenantFilter -sev Error
    }
}
