using namespace System.Net

Function Invoke-ListLogs {
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

    $Table = Get-CIPPTable

    $ReturnedLog = if ($Request.Query.ListLogs) {
        Get-AzDataTableEntity @Table -Property PartitionKey | Sort-Object -Unique PartitionKey | Select-Object PartitionKey | ForEach-Object {
            @{
                value = $_.PartitionKey
                label = $_.PartitionKey
            }
        }
    } else {
        if ($request.Query.Filter -eq 'True') {
            $LogLevel = if ($Request.query.Severity) { ($Request.query.Severity).split(',') } else { 'Info', 'Warn', 'Error', 'Critical', 'Alert' }
            $PartitionKey = $Request.query.DateFilter
            $username = $Request.Query.User
        } else {
            $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
            $PartitionKey = Get-Date -UFormat '%Y%m%d'
            $username = '*'
        }
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
        foreach ($Row in $Rows) {
            if ($AllowedTenants -notcontains 'AllTenants') {
                $TenantList = Get-Tenants -IncludeErrors
                if ($Row.Tenant -ne 'None' -and $Row.Tenant) {
                    $Tenant = $TenantList | Where-Object -Property defaultDomainName -EQ $Row.Tenant
                    if ($Tenant -and $Tenant.customerId -notin $AllowedTenants) {
                        continue
                    }
                }
            }
            $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                $Row.LogData | ConvertFrom-Json
            } else { $Row.LogData }
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
                } else {
                    'None'
                }
                AppId    = $Row.AppId
                IP       = $Row.IP
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ReturnedLog | Sort-Object -Property DateTime -Descending)
        })

}
