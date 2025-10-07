function Invoke-ListFunctionStats {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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
        } else {
            (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
        }
        $Table = Get-CIPPTable -tablename 'CippFunctionStats'

        if (!$PartitionKey) { $PartitionKey = 'Durable' }
        if (![string]::IsNullOrEmpty($TenantFilter) -and $TenantFilter -ne 'AllTenants') {
            $TenantQuery = " and (tenant eq '{0}' or Tenant eq '{0}' or Tenantid eq '{0}' or tenantid eq '{0}')" -f $TenantFilter
        } else {
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
    } catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Results  = @()
            Metadata = @{
                Filter    = $Filter
                Exception = $_.Exception.Message
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }

}
