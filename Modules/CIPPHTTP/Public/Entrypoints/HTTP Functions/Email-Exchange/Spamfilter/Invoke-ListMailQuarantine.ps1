function Invoke-ListMailQuarantine {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists quarantined email messages in Exchange Online Protection for a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Entity type: Email (default), SharePointOnline (files) or Teams (Teams messages)
    $EntityType = if ($Request.Query.EntityType -in @('Email', 'SharePointOnline', 'Teams')) { $Request.Query.EntityType } else { 'Email' }
    # EXO REST silently ignores -EntityType SharePointOnline; the documented filter for Safe Attachments
    # files is -QuarantineTypes SPOMalware. Email/Teams work fine via -EntityType.
    $EntityTypeParams = if ($EntityType -eq 'SharePointOnline') { @{ QuarantineTypes = 'SPOMalware' } } else { @{ EntityType = $EntityType } }

    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            $CustomerId = (Get-Tenants -TenantFilter $TenantFilter).customerId
            $PageSize = 1000
            if ($Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)) {
                # Manual pagination: return one page per request. The frontend chains requests via
                # Metadata.nextLink, which for this endpoint is the next Get-QuarantineMessage page number.
                $Page = if ($Request.Query.nextLink -match '^\d+$') { [int]$Request.Query.nextLink } else { 1 }
                $Results = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams (@{ PageSize = $PageSize; Page = $Page } + $EntityTypeParams) | Select-Object -ExcludeProperty *data.type*
                # Get-QuarantineMessage supports a maximum Page of 1000
                if (@($Results).Count -eq $PageSize -and $Page -lt 1000) {
                    $Metadata = [PSCustomObject]@{ nextLink = [string]($Page + 1) }
                }
                foreach ($Message in @($Results)) {
                    Add-CIPPQuarantineMessageProperties -Message $Message -Tenant $TenantFilter -CustomerId $CustomerId
                }
                $Results
            } else {
                $Page = 1
                $AllMessages = [System.Collections.Generic.List[object]]::new()
                do {
                    $Results = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams (@{ PageSize = $PageSize; Page = $Page } + $EntityTypeParams) | Select-Object -ExcludeProperty *data.type*
                    if ($Results) { $AllMessages.AddRange(@($Results)) }
                    $Page++
                } while (@($Results).Count -eq $PageSize)
                foreach ($Message in $AllMessages) {
                    Add-CIPPQuarantineMessageProperties -Message $Message -Tenant $TenantFilter -CustomerId $CustomerId
                }
                $AllMessages
            }
        } else {
            $Table = Get-CIPPTable -TableName cacheQuarantineMessages
            $PartitionKey = 'QuarantineMessage'
            $30MinutesAgo = (Get-Date).AddMinutes(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Filter = "PartitionKey eq '$PartitionKey' and Timestamp gt datetime'$30MinutesAgo'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Get-CIPPQueueData -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Mail Quarantine - All Tenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'MailQuarantineOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListMailQuarantineAllTenants'
                    }
                    SkipLog          = $true
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Messages = $Rows
                foreach ($message in $Messages) {
                    $messageObj = $message.QuarantineMessage | ConvertFrom-Json
                    # Older cache rows predate EntityType support and only contain Email entries
                    if (($messageObj.EntityType ?? 'Email') -ne $EntityType) { continue }
                    $messageObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $message.Tenant -Force
                    $messageObj
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    if (!$body) {
        $StatusCode = [HttpStatusCode]::OK
        $body = [PSCustomObject]@{
            Results  = @($GraphRequest | Where-Object -Property Identity -NE $null | Sort-Object -Property ReceivedTime -Descending )
            Metadata = $Metadata
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
