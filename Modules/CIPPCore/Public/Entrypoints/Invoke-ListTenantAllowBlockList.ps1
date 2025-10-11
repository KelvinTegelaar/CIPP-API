function Invoke-ListTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $ListTypes = 'Sender', 'Url', 'FileHash', 'IP'
    try {
        if ($TenantFilter -ne 'AllTenants') {
            $Results = $ListTypes | ForEach-Object -Parallel {
                Import-Module CIPPCore
                $TempResults = New-ExoRequest -tenantid $using:TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ ListType = $_ }
                $TempResults | Add-Member -MemberType NoteProperty -Name ListType -Value $_ -Force
                $TempResults | Add-Member -MemberType NoteProperty -Name Tenant -Value $using:TenantFilter -Force
                $TempResults | Select-Object -ExcludeProperty *'@data.type'*, *'(DateTime])'*
            } -ThrottleLimit 5
            $Metadata = [PSCustomObject]@{}
        } else {
            $Table = Get-CIPPTable -TableName 'cacheTenantAllowBlockList'
            $PartitionKey = 'TenantAllowBlockList'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
                $Results = @()
            } elseif (!$Rows -and !$RunningQueue) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Tenant Allow/Block List - All Tenants' -Link '/tenant/administration/allow-block-list?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'TenantAllowBlockListOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListTenantAllowBlockListAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress) | Out-Null
                $Results = @()
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Results = foreach ($Row in $Rows) {
                    $Row.Entry | ConvertFrom-Json
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Results = $ErrorMessage
    }

    if (!$Body) {
        $Body = [PSCustomObject]@{
            Results  = @($Results)
            Metadata = $Metadata
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
