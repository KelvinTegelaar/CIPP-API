function Invoke-ListCippCveManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
 
    $APIName      = $Request.Params.CIPPEndpoint
    $Headers      = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
 
    try {
        $CveCacheTable      = Get-CIPPTable -TableName 'CveCache'
        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
 
        # Build filter based on tenant selection
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $Filter = "customerId eq '$TenantFilter'"
        } else {
            $Filter = $null
        }
 
        if ($Filter) {
            $CveEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter $Filter
        } else {
            $CveEntries = Get-CIPPAzDataTableEntity @CveCacheTable
        }
 
        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved $($CveEntries.Count) CVE cache entries" -Sev 'Debug'
 
        # Load all exceptions and index by cveId for efficient lookup
        $AllExceptions   = Get-CIPPAzDataTableEntity @CveExceptionsTable
        $ExceptionsByCve = @{}
 
        foreach ($ex in $AllExceptions) {
            if (-not $ExceptionsByCve.ContainsKey($ex.cveId)) {
                $ExceptionsByCve[$ex.cveId] = [System.Collections.Generic.List[object]]::new()
            }
            $ExceptionsByCve[$ex.cveId].Add([PSCustomObject]@{
                customerId            = $ex.customerId
                exceptionType         = $ex.exceptionType
                exceptionComment      = $ex.exceptionComment
                exceptionCreatedBy    = $ex.exceptionCreatedBy
                exceptionReadableDate = $ex.exceptionReadableDate
                exceptionExpiry       = $ex.exceptionExpiry
            })
        }
 
        # Group by CVE ID and aggregate across devices/tenants
        $AggregatedCves = $CveEntries | Group-Object -Property cveId | ForEach-Object {
            $cveGroup   = $_.Group
            $firstEntry = $cveGroup[0]
 
            $deviceCount = ($cveGroup | Select-Object -ExpandProperty deviceName -Unique).Count
            $tenantCount = ($cveGroup | Select-Object -ExpandProperty customerId -Unique).Count
 
            $hasException    = $cveGroup | Where-Object { $_.hasException -eq $true }
            $exceptionStatus = if ($hasException) {
                $exceptionSources = ($cveGroup | Where-Object { $_.hasException -eq $true } | Select-Object -ExpandProperty exceptionSource -Unique) -join ', '
                if ($hasException.Count -eq $cveGroup.Count) { "All ($exceptionSources)" }
                else { "Partial ($exceptionSources)" }
            } else { 'None' }
 
            # Join exception details for this CVE
            $exceptions = if ($ExceptionsByCve.ContainsKey($firstEntry.cveId)) {
                @($ExceptionsByCve[$firstEntry.cveId])
            } else {
                @()
            }
 
            # Get the single most recent exception for this CVE
            $latestException = if ($exceptions.Count -gt 0) {
                $exceptions | Sort-Object -Property exceptionReadableDate -Descending | Select-Object -First 1
            } else { $null }
 
            [PSCustomObject]@{
                cveId                      = $firstEntry.cveId
                vulnerabilitySeverityLevel = $firstEntry.vulnerabilitySeverityLevel
                exploitabilityLevel        = $firstEntry.exploitabilityLevel
                softwareName               = $firstEntry.softwareName
                softwareVendor             = $firstEntry.softwareVendor
                softwareVersion            = $firstEntry.softwareVersion
                deviceCount                = $deviceCount
                tenantCount                = $tenantCount
                exceptionStatus            = $exceptionStatus
                hasException               = [bool]$hasException
                affectedTenants            = ($cveGroup | Select-Object -ExpandProperty customerId -Unique) -join ', '
                affectedDevices            = ($cveGroup | Select-Object -ExpandProperty deviceName -Unique | Select-Object -First 10) -join ', '
                exceptions                 = $exceptions
                exceptionType              = if ($latestException) { $latestException.exceptionType } else { '' }
                exceptionComment           = if ($latestException) { $latestException.exceptionComment } else { '' }
                exceptionCreatedBy         = if ($latestException) { $latestException.exceptionCreatedBy } else { '' }
                exceptionReadableDate      = if ($latestException) { $latestException.exceptionReadableDate } else { '' }
                exceptionExpiry            = if ($latestException) { $latestException.exceptionExpiry } else { '' }
            }
        }
 
        # Sort: Critical first, then by device count descending
        $SeverityOrder = @{ 'Critical' = 1; 'High' = 2; 'Medium' = 3; 'Low' = 4 }
 
        $SortedCves = $AggregatedCves | Sort-Object -Property @{
            Expression = { $SeverityOrder[$_.vulnerabilitySeverityLevel] }
        }, @{
            Expression = { $_.deviceCount }
            Descending = $true
        }
 
        Write-LogMessage -headers $Headers -API $APIName -message "Returning $($SortedCves.Count) aggregated CVEs" -Sev 'Debug'
 
        $StatusCode = [HttpStatusCode]::OK
        $Body       = @($SortedCves)
 
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve CVE data: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body       = @()
    }
 
    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    })
}