function Get-CIPPCVEReport {
    <#
    .SYNOPSIS
        Generates a CVE report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves Defender CVE data for a tenant from the reporting database
        Optimized for high-performance cross-referencing and memory efficiency.

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
        $AllExceptions      = Get-CIPPAzDataTableEntity @CveExceptionsTable
        $ExceptionsByCve    = @{}

        # Retrieve CVEs from database
        $RawCveData    = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'DefenderCVEs' | Where-Object { $_.RowKey -ne 'DefenderCVEs-Count' }
        $AllCachedCves = $RawCveData.Data | ConvertFrom-Json

        # Filter results by Tenant
        $RawCveItems = [System.Collections.Generic.List[object]]::new()

        if ($TenantFilter -eq 'AllTenants') {
            # Validate against active tenants to ensure we don't return orphaned data
            $TenantList = Get-Tenants -IncludeErrors
            foreach ($Item in $AllCachedCves) {
                if ($TenantList.defaultDomainName -contains $Item.customerId) {
                    [void]$RawCveItems.Add($Item)
                }
            }
        } else {
            $TenantList = Get-Tenants | Where-Object defaultDomainName -eq $TenantFilter
            foreach ($Item in $AllCachedCves) {
                if ($Item.customerId -eq $TenantFilter) {
                    [void]$RawCveItems.Add($Item)
                }
            }
        }

        if ($RawCveItems.Count -eq 0) {
            return @()
        }

        # Build filtered exception items
        foreach ($Ex in $AllExceptions) {
            if ($TenantList.defaultDomainName -contains $Ex.customerId -or $Ex.customerId -eq 'ALL'){
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

        # Process raw CVE items
        $CveMasterTable = @{}

        foreach ($Item in $RawCveItems) {
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
                        [void]$CveGroup.AffectedDevicesList.Add(@{ deviceName    = $Dev.deviceName })
                        if($Dev.registryPaths){[void]$CveGroup.RegistryPathList.Add(@{ deviceName = $Dev.deviceName
                                                                                       registryPaths = $Dev.registryPaths })}
                        if($Dev.diskPaths){[void]$CveGroup.DiskPathList.Add(@{ deviceName = $Dev.deviceName
                                                                               diskPaths = $Dev.diskPaths })}
                        $CveGroup.TotalDeviceCount ++
                }
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

            if ($ExceptionsByCve.ContainsKey($CveKey)){
                $Exceptions         = @($ExceptionsByCve[$CveKey])
                $HasException       = $true
                $ExceptionStatus    = if ($Exceptions.customerId -contains "ALL") { "All" } else { "Partial" }
                $ExceptionType      = @{ customerId = $Exceptions.customerId
                                        exceptionType = $Exceptions.exceptionType }
                $ExceptionComment   = @{ customerId = $Exceptions.customerId
                                        exceptionComment = $Exceptions.exceptionComment }
                $ExceptionCreatedBy = @{ customerId = $Exceptions.customerId
                                        exceptionCreatedBy = $Exceptions.exceptionCreatedBy }
                $ExceptionDate      = @{ customerId = $Exceptions.customerId
                                        exceptionDate = $Exceptions.exceptionDate }
                $ExceptionExpiry    = @{ customerId = $Exceptions.customerId
                                        exceptionExpiry = $Exceptions.exceptionExpiry }
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

    } catch {
        Write-LogMessage -API 'CVEReport' -tenant $TenantFilter -message "Failed to generate CVE report: $($_.Exception.Message)" -sev Error
        throw
    }
}
