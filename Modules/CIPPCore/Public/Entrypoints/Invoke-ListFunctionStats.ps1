using namespace System.Net

function Invoke-ListFunctionStats {
    <#
    .SYNOPSIS
    List CIPP function execution statistics and performance metrics
    
    .DESCRIPTION
    Retrieves execution statistics for CIPP functions including execution count, duration metrics, and performance analysis with time-based filtering.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Monitoring
    Summary: List Function Stats
    Description: Retrieves execution statistics for CIPP functions and standards including execution count, total duration, maximum duration, and average duration with time-based filtering.
    Tags: Monitoring,Statistics,Performance
    Parameter: tenantFilter (string) [query] - Tenant to filter statistics for (use 'AllTenants' for all tenants)
    Parameter: FunctionType (string) [query] - Function type to filter (default: 'Durable')
    Parameter: Time (number) [query] - Time value for filtering
    Parameter: Interval (string) [query] - Time interval: Days, Hours, or Minutes
    Response: Returns a response object with the following properties:
    Response: - Results (object): Contains Functions and Standards arrays
    Response: - Results.Functions (array): Array of function statistics objects with the following properties:
    Response: - Name (string): Function name
    Response: - ExecutionCount (number): Number of times the function was executed
    Response: - TotalSeconds (number): Total execution time in seconds
    Response: - MaxSeconds (number): Maximum execution time in seconds
    Response: - AvgSeconds (number): Average execution time in seconds
    Response: - Results.Standards (array): Array of standard statistics objects with the same properties as Functions
    Response: - Metadata (object): Contains Filter and optional Exception information
    Example: {
      "Results": {
        "Functions": [
          {
            "Name": "ListUsers",
            "ExecutionCount": 45,
            "TotalSeconds": 67.5,
            "MaxSeconds": 3.2,
            "AvgSeconds": 1.5
          }
        ],
        "Standards": [
          {
            "Name": "MFA Enforcement",
            "ExecutionCount": 12,
            "TotalSeconds": 24.0,
            "MaxSeconds": 2.1,
            "AvgSeconds": 2.0
          }
        ]
      },
      "Metadata": {
        "Filter": "PartitionKey eq 'Durable' and Start ge datetime'2024-01-14T10:00:00.000Z'"
      }
    }
    Error: Returns error details if the operation fails to retrieve function statistics.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter
        $PartitionKey = $Request.Query.FunctionType
        $Time = $Request.Query.Time
        $Interval = $Request.Query.Interval

        $Timestamp = if (![string]::IsNullOrEmpty($Interval) -and ![string]::IsNullOrEmpty($Time)) {
            switch ($Interval) {
                'Days' {
                    (Get-Date).AddDays(-$Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                }
                'Hours' {
                    (Get-Date).AddHours(-$Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                }
                'Minutes' {
                    (Get-Date).AddMinutes(-$Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                }
            }
        }
        else {
            (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
        }
        $Table = Get-CIPPTable -tablename 'CippFunctionStats'

        if (!$PartitionKey) { $PartitionKey = 'Durable' }
        if (![string]::IsNullOrEmpty($TenantFilter) -and $TenantFilter -ne 'AllTenants') {
            $TenantQuery = " and (tenant eq '{0}' or Tenant eq '{0}' or Tenantid eq '{0}' or tenantid eq '{0}')" -f $TenantFilter
        }
        else {
            $TenantQuery = ''
        }
        $Filter = "PartitionKey eq '{0}' and Start ge datetime'{1}'{2}" -f $PartitionKey, $Timestamp, $TenantQuery

        $Entries = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        $FunctionList = $Entries | Group-Object -Property FunctionName
        $StandardList = $Entries | Where-Object { $_.Standard } | Group-Object -Property Standard
        $FunctionStats = foreach ($Function in $FunctionList) {
            $Stats = $Function.Group | Measure-Object -Property Duration -AllStats
            [PSCustomObject]@{
                'Name'           = $Function.Name
                'ExecutionCount' = $Function.Count
                'TotalSeconds'   = $Stats.Sum
                'MaxSeconds'     = $Stats.Maximum
                'AvgSeconds'     = $Stats.Average
            }
        }
        $StandardStats = foreach ($Standard in $StandardList) {
            $Stats = $Standard.Group | Measure-Object -Property Duration -AllStats
            [PSCustomObject]@{
                'Name'           = $Standard.Name
                'ExecutionCount' = $Standard.Count
                'TotalSeconds'   = $Stats.Sum
                'MaxSeconds'     = $Stats.Maximum
                'AvgSeconds'     = $Stats.Average
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results  = @{
                Functions = @($FunctionStats)
                Standards = @($StandardStats)
            }
            Metadata = @{
                Filter = $Filter
            }
        }
    }
    catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Results  = @()
            Metadata = @{
                Filter    = $Filter
                Exception = $_.Exception.Message
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        }) -Clobber

}
