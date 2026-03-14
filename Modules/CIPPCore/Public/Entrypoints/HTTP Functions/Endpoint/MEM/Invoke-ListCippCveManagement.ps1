function Invoke-ListCippCveManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter

try {
    # Get the CveCache table
    $CveCacheTable = Get-CIPPTable -TableName 'CveCache'
    
    # Get tenant filter from request
    $TenantFilter = $Request.Query.TenantFilter
    
    # Build filter based on tenant selection
    if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
        $Filter = "customerId eq '$TenantFilter'"
    } else {
        $Filter = $null
    }
    
    # Get all CVE cache entries
    Write-Host "Fetching CVE cache entries with filter: $Filter"
    if ($Filter) {
        $CveEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter $Filter
    } else {
        $CveEntries = Get-CIPPAzDataTableEntity @CveCacheTable
    }
    
    Write-Host "Retrieved $($CveEntries.Count) CVE entries from cache"
    
    # Group by CVE ID and aggregate
    $AggregatedCves = $CveEntries | Group-Object -Property cveId | ForEach-Object {
        $cveGroup = $_.Group
        $firstEntry = $cveGroup[0]
        
        # Count unique devices and tenants
        $deviceCount = ($cveGroup | Select-Object -ExpandProperty deviceName -Unique).Count
        $tenantCount = ($cveGroup | Select-Object -ExpandProperty customerId -Unique).Count
        
        # Check exception status
        $hasException = $cveGroup | Where-Object { $_.hasException -eq $true }
        $exceptionStatus = if ($hasException) {
            $exceptionSources = ($cveGroup | Where-Object { $_.hasException -eq $true } | Select-Object -ExpandProperty exceptionSource -Unique) -join ', '
            if ($hasException.Count -eq $cveGroup.Count) {
                "All ($exceptionSources)"
            } else {
                "Partial ($exceptionSources)"
            }
        } else {
            "None"
        }
        
        [PSCustomObject]@{
            cveId                       = $firstEntry.cveId
            vulnerabilitySeverityLevel  = $firstEntry.vulnerabilitySeverityLevel
            exploitabilityLevel         = $firstEntry.exploitabilityLevel
            softwareName                = $firstEntry.softwareName
            softwareVendor              = $firstEntry.softwareVendor
            softwareVersion             = $firstEntry.softwareVersion
            recommendedSecurityUpdate   = $firstEntry.recommendedSecurityUpdate
            deviceCount                 = $deviceCount
            tenantCount                 = $tenantCount
            exceptionStatus             = $exceptionStatus
            hasException                = [bool]$hasException
            affectedTenants             = ($cveGroup | Select-Object -ExpandProperty customerId -Unique) -join ', '
            affectedDevices             = ($cveGroup | Select-Object -ExpandProperty deviceName -Unique | Select-Object -First 10) -join ', '
        }
    }
    
    # Sort by severity (Critical first) then by device count
    $SeverityOrder = @{
        'Critical' = 1
        'High'     = 2
        'Medium'   = 3
        'Low'      = 4
    }
    
    $SortedCves = $AggregatedCves | Sort-Object -Property @{
        Expression = { $SeverityOrder[$_.vulnerabilitySeverityLevel] }
    }, @{
        Expression = { $_.deviceCount }
        Descending = $true
    }
    
    Write-Host "Aggregated into $($SortedCves.Count) unique CVEs"
    
    $StatusCode = [HttpStatusCode]::OK
    $Body = @($SortedCves)
    
} catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve CVE data: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::InternalServerError
    $Body = @()
}

return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    })
}
