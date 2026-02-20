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

    # Extract filter parameters from InputValue
    $ExploitabilityLevels = [System.Collections.Generic.List[string]]::new()
    if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
        # Number inputs are stored directly
        $AgeThresholdHours = if ($InputValue.VulnerabilityAgeHours) { [int]$InputValue.VulnerabilityAgeHours } else { 0 }
        # Autocomplete inputs store value in .value subproperty
        $CVSSSeverity = if ($InputValue.CVSSSeverity.value) { $InputValue.CVSSSeverity.value } else { 'low' }
        # Multi-select autocomplete returns array of objects with .value
        if ($InputValue.ExploitabilityLevels) {
            foreach ($level in $InputValue.ExploitabilityLevels) {
                $ExploitabilityLevels.Add($(if ($level.value) { $level.value } else { $level }))
            }
        }
    } else {
        # Backward compatibility: simple value = hours threshold
        $AgeThresholdHours = if ($InputValue) { [int]$InputValue } else { 0 }
        $CVSSSeverity = 'low'
    }

    # Convert CVSS severity to minimum score
    $CVSSMinScore = switch ($CVSSSeverity.ToLower()) {
        'critical' { 9.0 }
        'high' { 7.0 }
        'medium' { 4.0 }
        'low' { 0.0 }
        default { 0.0 }
    }

    try {
        $VulnerabilityRequest = New-GraphGetRequest -tenantid $TenantFilter -uri 'https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine' -scope 'https://api.securitycenter.microsoft.com/.default'

        if ($VulnerabilityRequest) {
            $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Group by CVE ID and create objects for each vulnerability
            $VulnerabilityGroups = $VulnerabilityRequest | Where-Object { $_.cveId } | Group-Object cveId

            foreach ($Group in $VulnerabilityGroups) {
                $FirstVuln = $Group.Group | Sort-Object firstSeenTimestamp | Select-Object -First 1
                $HoursOld = [math]::Round(((Get-Date) - [datetime]$FirstVuln.firstSeenTimestamp).TotalHours)

                # Skip if vulnerability is not old enough
                if ($HoursOld -lt $AgeThresholdHours) {
                    continue
                }

                # Skip if CVSS score is below minimum threshold
                $VulnCVSS = if ($null -ne $FirstVuln.cvssScore) { [double]$FirstVuln.cvssScore } else { 0 }
                if ($VulnCVSS -lt $CVSSMinScore) {
                    continue
                }

                # Skip if exploitability level doesn't match filter (unless "All" is selected)
                if ($ExploitabilityLevels.Count -gt 0 -and 'All' -notin $ExploitabilityLevels) {
                    if ($FirstVuln.exploitabilityLevel -notin $ExploitabilityLevels) {
                        continue
                    }
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
                    SoftwareName         = $FirstVuln.softwareName
                    SoftwareVendor       = $FirstVuln.softwareVendor
                    SoftwareVersion      = $FirstVuln.softwareVersion
                    CVSSScore            = $FirstVuln.cvssScore
                    ExploitabilityLevel  = $FirstVuln.exploitabilityLevel
                    RecommendedUpdate    = $FirstVuln.recommendedSecurityUpdate
                    RecommendedUpdateId  = $FirstVuln.recommendedSecurityUpdateId
                    RecommendedUpdateUrl = $FirstVuln.recommendedSecurityUpdateUrl
                    AffectedDevices      = $AffectedDevices
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
