function get-DefenderCVEs {
    <#
    .SYNOPSIS
        Caches all vulnerabilities devices for a tenant

    .PARAMETER TenantFilter
        The tenant to cache vulnerabilities for

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

        if (-not $AllVulns) {
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -sev 'Warning'
            return
        }

        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) CVE records from Defender TVM" -sev 'Info'
        try{
        # Initialize a tracker for this tenant session
        $CveAggregator = @{}
        }catch{
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Aggregator Failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        }
        try{
        # Group the raw TVM records into unified CVE buckets
        foreach ($Vuln in $AllVulns) {
            $CveId = $Vuln.cveId
            try{
            if (-not $CveAggregator.ContainsKey($CveId)) {
                # Establish global CVE & software properties for this specific tenant
                $CveAggregator[$CveId] = @{
                    cveId                        = $CveId
                    customerId                   = $TenantFilter
                    softwareVendor               = $Vuln.softwareVendor               ?? ''
                    softwareName                 = $Vuln.softwareName                 ?? ''
                    vulnerabilitySeverityLevel   = $Vuln.vulnerabilitySeverityLevel   ?? ''
                    recommendedSecurityUpdate    = $Vuln.recommendedSecurityUpdate    ?? ''
                    recommendedSecurityUpdateUrl = $Vuln.recommendedSecurityUpdateUrl ?? ''
                    exploitabilityLevel          = $Vuln.exploitabilityLevel          ?? ''

                    # Arrays to collect device metadata efficiently
                    AffectedDevices              = [System.Collections.Generic.List[object]]::new()
                }
            }
        }catch{
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Failed to establish global: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        }
            try{
            # Extract properties specific to this device instance
            $DevicePayload = @{
                deviceId        = ($Vuln.deviceId -join ',') ?? ''
                deviceName      = ($Vuln.deviceName -join ',') ?? ''
                osVersion       = $Vuln.osVersion ?? ''
                softwareVersion = ($Vuln.softwareVersion -join ',') ?? ''
                diskPaths       = if ($Vuln.diskPaths) { $Vuln.diskPaths -join ';' } else { '' }
                registryPaths   = if ($Vuln.registryPaths) { $Vuln.registryPaths -join ';' } else { '' }
            }
        }catch{
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Failed to extract: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        }
            # Append to our tracking list
            [void]$CveAggregator[$CveId].AffectedDevices.Add($DevicePayload)
        }
    }catch{
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Allover Build: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
    }

        $Entities = [System.Collections.Generic.List[object]]::new()

        foreach ($CveKey in $CveAggregator.Keys) {
            $CveData = $CveAggregator[$CveKey]

            # Flatten or convert device info arrays into a compact, compressed JSON string
            $CompactDeviceJson = $CveData.AffectedDevices | ConvertTo-Json -Compress

            [void]$Entities.Add(@{
                PartitionKey                 = $CveKey
                RowKey                       = $TenantFilter # RowKey becomes just the Tenant, ensuring 1 row per CVE per Tenant
                customerId                   = $TenantFilter
                cveId                        = $CveKey
                softwareVendor               = $CveData.softwareVendor
                softwareName                 = $CveData.softwareName
                vulnerabilitySeverityLevel   = $CveData.vulnerabilitySeverityLevel
                recommendedSecurityUpdate    = $CveData.recommendedSecurityUpdate
                recommendedSecurityUpdateUrl = $CveData.recommendedSecurityUpdateUrl
                exploitabilityLevel          = $CveData.exploitabilityLevel

                # Meta aggregation counts
                deviceCount                  = $CveData.AffectedDevices.Count

                # All individual device variations compressed safely inside a single field
                deviceDetailsJson            = $CompactDeviceJson

                lastUpdated                  = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
            })
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "No valid CVE records to cache" -sev 'Warning'
            return
        }

        $SuccessCount = 0
        $FailCount    = 0

        $UniqueCves    = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Retrieved $UniqueCves Unique CVEs" -sev 'Info'

        return $Entities

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
