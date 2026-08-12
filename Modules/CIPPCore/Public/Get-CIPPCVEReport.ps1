function Get-CIPPCVEReport {
    <#
    .SYNOPSIS
        Generates a CVE report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves Defender CVE data for a tenant from the reporting database.

        Rows are folded one at a time: each row's Data blob is parsed, tenant-validated
        and merged into the master table before the next row is touched, so the parsed
        PSCustomObject graphs - the most expensive representation of the dataset - never
        all exist at once. This previously materialised every cached row, a parsed copy
        of every Data blob and a third list of references before aggregation began,
        which for AllTenants is the entire CVE cache held three ways on the HTTP worker
        pool's shared heap.

    .PARAMETER TenantFilter
        The tenant to generate the report for, or 'AllTenants'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        # Retrieve Exceptions from Exception database
        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
        $AllExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable

        # AllTenants rows are validated against the active tenant list so orphaned data is
        # never returned. A HashSet turns that from a scan of the tenant list per row into
        # a single lookup. Single-tenant reads are already partition-filtered by
        # Get-CIPPDbItem, so no per-row validation is needed there.
        $ActiveDomains = $null
        if ($TenantFilter -eq 'AllTenants') {
            $TenantList = Get-Tenants -IncludeErrors
            $ActiveDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Tenant in $TenantList) { [void]$ActiveDomains.Add([string]$Tenant.defaultDomainName) }
        } else {
            $TenantList = Get-Tenants -TenantFilter $TenantFilter
        }

        # Process raw CVE items
        $CveMasterTable = @{}
        $RowCount = 0

        foreach ($Row in Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefenderCVEs') {
            if ($Row.RowKey -eq 'DefenderCVEs-Count' -or -not $Row.Data) { continue }

            $Item = $Row.Data | ConvertFrom-Json
            if ($ActiveDomains -and -not $ActiveDomains.Contains([string]$Item.customerId)) { continue }
            $RowCount++

            # The Data blob carries the CVE id as its PartitionKey - the row's own
            # PartitionKey is the tenant.
            $CveId = $Item.PartitionKey

            if (-not $CveMasterTable.ContainsKey($CveId)) {
                $CveMasterTable[$CveId] = @{
                    cveId                      = $CveId
                    vulnerabilitySeverityLevel = $Item.vulnerabilitySeverityLevel
                    exploitabilityLevel        = $Item.exploitabilityLevel
                    softwareName               = $Item.softwareName
                    softwareVendor             = $Item.softwareVendor
                    softwareVersion            = $Item.softwareVersion
                    lastUpdated                = $Item.lastUpdated
                    TotalDeviceCount           = 0
                    AffectedTenantsList        = [System.Collections.Generic.List[object]]::new()
                    AffectedDevicesList        = [System.Collections.Generic.List[object]]::new()
                    DiskPathList               = [System.Collections.Generic.List[object]]::new()
                    RegistryPathList           = [System.Collections.Generic.List[object]]::new()
                    ExceptionMatchCount        = 0
                    TotalTenantGroupCount      = 0
                    ExceptionSources           = [System.Collections.Generic.HashSet[string]]::new()
                }
            }

            $CveGroup = $CveMasterTable[$CveId]
            $CveGroup.TotalTenantGroupCount++

            [void]$CveGroup.AffectedTenantsList.Add(@{ customerId = $Item.customerId })

            # Unpack the device JSON details from the row
            if ($Item.deviceDetailsJson) {
                $Devices = ConvertFrom-Json $Item.deviceDetailsJson | Sort-Object -Property deviceName -Unique
                foreach ($Dev in $Devices) {
                    [void]$CveGroup.AffectedDevicesList.Add(@{ deviceName = $Dev.deviceName })
                    if ($Dev.registryPaths) {
                        [void]$CveGroup.RegistryPathList.Add(@{ deviceName = $Dev.deviceName
                                registryPaths                              = $Dev.registryPaths
                            })
                    }
                    if ($Dev.diskPaths) {
                        [void]$CveGroup.DiskPathList.Add(@{ deviceName = $Dev.deviceName
                                diskPaths                              = $Dev.diskPaths
                            })
                    }
                    $CveGroup.TotalDeviceCount ++
                }
            }
        }

        if ($RowCount -eq 0) {
            return @()
        }

        # Build filtered exception items
        $ExceptionsByCve = @{}

        foreach ($Ex in $AllExceptions) {
            $InScope = if ($ActiveDomains) { $ActiveDomains.Contains([string]$Ex.customerId) } else { $TenantList.defaultDomainName -contains $Ex.customerId }
            if ($InScope -or $Ex.customerId -eq 'ALL') {
                if (-not $ExceptionsByCve.ContainsKey($Ex.cveId)) {
                    $ExceptionsByCve[$Ex.cveId] = [System.Collections.Generic.List[object]]::new()
                }

                [void]$ExceptionsByCve[$Ex.cveId].Add([PSCustomObject]@{
                        cveId              = $Ex.cveId
                        customerId         = $Ex.customerId
                        exceptionType      = $Ex.exceptionType
                        exceptionSource    = $Ex.exceptionSource
                        exceptionComment   = $Ex.exceptionComment
                        exceptionCreatedBy = $Ex.exceptionCreatedBy
                        exceptionDate      = $Ex.exceptionReadableDate
                        exceptionExpiry    = $Ex.exceptionExpiry
                    })
            }
        }

        # Combine filtered results
        $SortedCves = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($CveKey in $CveMasterTable.Keys) {
            $Target = $CveMasterTable[$CveKey]
            $ExceptionStatus = 'None'
            $HasException = $false
            $Exceptions = @{}
            $ExceptionType = ''
            $ExceptionComment = ''
            $ExceptionCreatedBy = ''
            $ExceptionDate = ''
            $ExceptionExpiry = ''

            if ($ExceptionsByCve.ContainsKey($CveKey)) {
                $Exceptions = @($ExceptionsByCve[$CveKey])
                $HasException = $true
                $ExceptionStatus = if ($Exceptions.customerId -contains "ALL") { "All" } else { "Partial" }
                $ExceptionType = @{ customerId = $Exceptions.customerId
                    exceptionType              = $Exceptions.exceptionType
                }
                $ExceptionComment = @{ customerId = $Exceptions.customerId
                    exceptionComment              = $Exceptions.exceptionComment
                }
                $ExceptionCreatedBy = @{ customerId = $Exceptions.customerId
                    exceptionCreatedBy              = $Exceptions.exceptionCreatedBy
                }
                $ExceptionDate = @{ customerId = $Exceptions.customerId
                    exceptionDate              = $Exceptions.exceptionDate
                }
                $ExceptionExpiry = @{ customerId = $Exceptions.customerId
                    exceptionExpiry              = $Exceptions.exceptionExpiry
                }
            }

            [void]$SortedCves.Add([PSCustomObject]@{
                    cveId                      = $Target.cveId
                    vulnerabilitySeverityLevel = $Target.vulnerabilitySeverityLevel
                    exploitabilityLevel        = $Target.exploitabilityLevel
                    softwareName               = $Target.softwareName
                    softwareVendor             = $Target.softwareVendor
                    softwareVersion            = $Target.softwareVersion
                    deviceCount                = $Target.TotalDeviceCount
                    tenantCount                = $Target.TotalTenantGroupCount
                    registryPaths              = $Target.RegistryPathList
                    diskPaths                  = $Target.DiskPathList
                    exceptionStatus            = $ExceptionStatus
                    hasException               = $HasException
                    affectedTenants            = $Target.AffectedTenantsList
                    affectedDevices            = $Target.AffectedDevicesList
                    exceptionType              = $ExceptionType
                    exceptionComment           = $ExceptionComment
                    exceptionCreatedBy         = $ExceptionCreatedBy
                    exceptionDate              = $ExceptionDate
                    exceptionExpiry            = $ExceptionExpiry
                    cacheTimeStamp             = $Target.lastUpdated
                })
        }

        return  $SortedCves | Sort-Object -Property cveId

    }
    catch {
        Write-LogMessage -API 'CVEReport' -tenant $TenantFilter -message "Failed to generate CVE report: $($_.Exception.Message)" -sev Error
        throw
    }
}
