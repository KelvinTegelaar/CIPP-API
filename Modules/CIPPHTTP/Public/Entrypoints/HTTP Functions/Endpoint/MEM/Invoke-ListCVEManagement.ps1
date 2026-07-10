function Invoke-ListCVEManagement {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Security.Read
    #>

    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    if ($UseReportDB -eq 'true') {
        try {
            $GraphRequest = Get-CIPPCVEReport -TenantFilter $TenantFilter -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
            $SortedCves = $GraphRequest
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'running cve report' -sev 'info'
        } catch {
            Write-Host "Error retrieving CVEs from report database: $($_.Exception.Message)"
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'Error retrieving' -sev 'info'
        }
    } else {
        try {
            Write-LogMessage -API 'ListCVEManagement' -tenant $TenantFilter -message 'retrieving CVEs' -sev 'info'
            $GraphRequest = get-DefenderCVEs -TenantFilter $TenantFilter

            # Retrieve Exceptions from Exception database
            $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
            $AllExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable
            $ExceptionsByCve = @{}

            # Retrieve CVEs from database
            $RawCveItems = $GraphRequest
            $AllCachedCves = $RawCveData

            $TenantList = Get-Tenants | Where-Object defaultDomainName -EQ $TenantFilter

            if ($RawCveItems.Count -eq 0) {
                return @()
            }

            foreach ($Ex in $AllExceptions) {
                if ($TenantList.defaultDomainName -contains $Ex.customerId -or $Ex.customerId -eq 'ALL') {
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

            # Merge all results
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
                    $ExceptionStatus = if ($Exceptions.customerId -contains 'ALL') { 'All' } else { 'Partial' }
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
                $StatusCode = [HttpStatusCode]::OK
            }

        } catch {
            Write-Host "Error retrieving CVEs: $($_.Exception.Message)"
            $StatusCode = [HttpStatusCode]::InternalServerError
            $SortedCves = $_.Exception.Message
        }
    }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($SortedCves | Sort-Object -Property cveId)
    }
}
