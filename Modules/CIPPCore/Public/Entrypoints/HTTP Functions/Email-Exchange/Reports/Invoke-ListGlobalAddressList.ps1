function Invoke-ListGlobalAddressList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName CacheGlobalAddressList
            $PartitionKey = 'GlobalAddressList'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading global address list for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Global Address List - All Tenants' -Link '/email/reports/global-address-list?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading global address list for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'GlobalAddressListOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListGlobalAddressListAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $GAL = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } else {
            $GAL = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{ResultSize = 'unlimited'; SortBy = 'DisplayName' } `
                -Select 'Identity, DisplayName, Alias, PrimarySmtpAddress, ExternalDirectoryObjectId, HiddenFromAddressListsEnabled, EmailAddresses, IsDirSynced, SKUAssigned, RecipientType, RecipientTypeDetails, AddressListMembership' |
                Select-Object -ExcludeProperty *odata*, *data.type*
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::Forbidden
        $GAL = $ErrorMessage.NormalizedError
    }

    $Body = [PSCustomObject]@{
        Results  = @($GAL | Where-Object { $_.Id -ne $null })
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
