using namespace System.Net

function Invoke-ListLogs {
    <#
    .SYNOPSIS
    List CIPP application logs with filtering and search capabilities
    
    .DESCRIPTION
    Retrieves CIPP application logs with support for date filtering, severity filtering, user filtering, and tenant access control
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Logging
    Summary: List Logs
    Description: Retrieves CIPP application logs with comprehensive filtering options including date ranges, severity levels, user filtering, and tenant-based access control
    Tags: Logging,Monitoring,Audit
    Parameter: ListLogs (boolean) [query] - Whether to list available log partition keys
    Parameter: Filter (boolean) [query] - Whether to apply filtering to logs
    Parameter: Severity (string) [query] - Comma-separated list of severity levels to include (Info, Warn, Error, Critical, Alert)
    Parameter: DateFilter (string) [query] - Date filter in yyyyMMdd format
    Parameter: StartDate (string) [query] - Start date for range filtering in yyyyMMdd format
    Parameter: EndDate (string) [query] - End date for range filtering in yyyyMMdd format
    Parameter: User (string) [query] - Username filter (supports wildcards)
    Response: When ListLogs=true, returns an array of partition key objects:
    Response: - value (string): Partition key value
    Response: - label (string): Partition key label
    Response: When ListLogs=false, returns an array of log objects with the following properties:
    Response: - DateTime (string): Log timestamp
    Response: - Tenant (string): Tenant identifier
    Response: - API (string): API endpoint that generated the log
    Response: - Message (string): Log message
    Response: - User (string): Username that triggered the action
    Response: - Severity (string): Log severity level
    Response: - LogData (object): Additional log data (JSON object if available)
    Response: - TenantID (string): Tenant ID or 'None' if not applicable
    Response: - AppId (string): Application ID that generated the log
    Response: - IP (string): IP address of the request
    Example: [
      {
        "DateTime": "2024-01-15T10:30:00Z",
        "Tenant": "contoso.onmicrosoft.com",
        "API": "ListUsers",
        "Message": "Successfully retrieved 150 users",
        "User": "admin@contoso.com",
        "Severity": "Info",
        "LogData": {
          "userCount": 150,
          "filterApplied": "accountEnabled eq true"
        },
        "TenantID": "12345678-1234-1234-1234-123456789012",
        "AppId": "cipp-app",
        "IP": "192.168.1.100"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable

    $ReturnedLog = if ($Request.Query.ListLogs) {
        Get-AzDataTableEntity @Table -Property PartitionKey | Sort-Object -Unique PartitionKey | Select-Object PartitionKey | ForEach-Object {
            @{
                value = $_.PartitionKey
                label = $_.PartitionKey
            }
        }
    }
    else {
        if ($request.Query.Filter -eq 'True') {
            $LogLevel = if ($Request.Query.Severity) { ($Request.query.Severity).split(',') } else { 'Info', 'Warn', 'Error', 'Critical', 'Alert' }
            $PartitionKey = $Request.Query.DateFilter
            $username = $Request.Query.User ?? '*'

            $StartDate = $Request.Query.StartDate ?? $Request.Query.DateFilter
            $EndDate = $Request.Query.EndDate ?? $Request.Query.DateFilter

            if ($StartDate -and $EndDate) {
                # Collect logs for each partition key date in range
                $PartitionKeys = for ($Date = [datetime]::ParseExact($StartDate, 'yyyyMMdd', $null); $Date -le [datetime]::ParseExact($EndDate, 'yyyyMMdd', $null); $Date = $Date.AddDays(1)) {
                    $PartitionKey = $Date.ToString('yyyyMMdd')
                    "PartitionKey eq '$PartitionKey'"
                }
                $Filter = $PartitionKeys -join ' or '
            }
            elseif ($StartDate) {
                $Filter = "PartitionKey eq '{0}'" -f $StartDate
            }
            else {
                $Filter = "PartitionKey eq '{0}'" -f (Get-Date -UFormat '%Y%m%d')
            }
        }
        else {
            $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
            $PartitionKey = Get-Date -UFormat '%Y%m%d'
            $username = '*'
            $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
        }
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        Write-Host "Getting logs for filter: $Filter, LogLevel: $LogLevel, Username: $username"

        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Severity -in $LogLevel -and $_.Username -like $username }

        if ($AllowedTenants -notcontains 'AllTenants') {
            $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
        }

        foreach ($Row in $Rows) {
            if ($AllowedTenants -contains 'AllTenants' -or ($AllowedTenants -notcontains 'AllTenants' -and ($TenantList.defaultDomainName -contains $Row.Tenant -or $Row.Tenant -eq 'CIPP' -or $TenantList.customerId -contains $Row.TenantId)) ) {

                $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                    $Row.LogData | ConvertFrom-Json
                }
                else { $Row.LogData }
                [PSCustomObject]@{
                    DateTime = $Row.Timestamp
                    Tenant   = $Row.Tenant
                    API      = $Row.API
                    Message  = $Row.Message
                    User     = $Row.Username
                    Severity = $Row.Severity
                    LogData  = $LogData
                    TenantID = if ($Row.TenantID -ne $null) {
                        $Row.TenantID
                    }
                    else {
                        'None'
                    }
                    AppId    = $Row.AppId
                    IP       = $Row.IP
                }
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ReturnedLog | Sort-Object -Property DateTime -Descending)
        })

}
