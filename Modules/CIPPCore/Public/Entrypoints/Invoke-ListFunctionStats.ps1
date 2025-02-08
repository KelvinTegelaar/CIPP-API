using namespace System.Net

Function Invoke-ListFunctionStats {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    # Interact with query parameters or the body of the request.

    try {
        $TenantFilter = $Request.Query.TenantFilter
        $PartitionKey = $Request.Query.FunctionType

        $Timestamp = if (![string]::IsNullOrEmpty($Request.Query.Interval) -and ![string]::IsNullOrEmpty($Request.Query.Time)) {
            switch ($Request.Query.Interval) {
                'Days' {
                    (Get-Date).AddDays(-$Request.Query.Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                }
                'Hours' {
                    (Get-Date).AddHours(-$Request.Query.Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                }
                'Minutes' {
                    (Get-Date).AddMinutes(-$Request.Query.Time).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
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
        $Status = [HttpStatusCode]::OK
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
        $Status = [HttpStatusCode]::BadRequest
        $Body = @{
            Results  = @()
            Metadata = @{
                Filter    = $Filter
                Exception = $_.Exception.Message
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $Status
            Body       = $Body
        }) -Clobber

}
