using namespace System.Net

function Invoke-ListLogs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
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
    } else {
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
            } elseif ($StartDate) {
                $Filter = "PartitionKey eq '{0}'" -f $StartDate
            } else {
                $Filter = "PartitionKey eq '{0}'" -f (Get-Date -UFormat '%Y%m%d')
            }
        } else {
            $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
            $PartitionKey = Get-Date -UFormat '%Y%m%d'
            $username = '*'
            $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
        }
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        Write-Host "Getting logs for filter: $Filter, LogLevel: $LogLevel, Username: $username"

        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object {
            $_.Severity -in $LogLevel -and $_.Username -like $username
        }

        # Pre-fetch tenants only if filtering is needed
        $TenantLookup = @{}
        if ($AllowedTenants -ne 'AllTenants') {
            $TenantLookup = Get-Tenants -IncludeErrors | Group-Object -Property defaultDomainName -AsHashTable -AsString
        }

        foreach ($Row in $Rows) {
            if ($AllowedTenants -ne 'AllTenants' -and $Row.Tenant -and $Row.Tenant -ne 'None') {
                $Tenant = $TenantLookup[$Row.Tenant]
                if (!$Tenant -or $Tenant.customerId -notin $AllowedTenants) { continue }
            }

            $LogData = $null
            if ($Row.LogData) {
                try {
                    $LogData = $Row.LogData | ConvertFrom-Json
                } catch {
                    $LogData = $Row.LogData
                }
            }

            [PSCustomObject]@{
                DateTime = $Row.Timestamp
                Tenant   = $Row.Tenant
                API      = $Row.API
                Message  = $Row.Message
                User     = $Row.Username
                Severity = $Row.Severity
                LogData  = $LogData
                TenantID = $Row.TenantID ?? 'None'
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
