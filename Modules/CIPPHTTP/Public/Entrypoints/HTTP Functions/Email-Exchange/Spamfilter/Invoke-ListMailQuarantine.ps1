function Invoke-ListMailQuarantine {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists quarantined email messages in Exchange Online Protection for a tenant.
        Supports server-side filtering via Get-QuarantineMessage parameters.
        Default behavior returns one page (100 rows, last 7 days) unless fetchAll=true.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $body = $null
    $StatusCode = [HttpStatusCode]::OK
    $GraphRequest = @()
    $Metadata = $null

    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            $Input = @{
                pageSize = $Request.Query.pageSize
                page     = $Request.Query.page
                nextLink = $Request.Query.nextLink
            }
            foreach ($Key in @('days', 'startDate', 'endDate', 'sender', 'recipient', 'messageId', 'subject', 'subjectExact', 'quarantineType', 'releaseStatus', 'policyTypes', 'policyName', 'senderDomain', 'recipientDomain', 'entityType')) {
                if ($null -ne $Request.Query.$Key) {
                    $Input[$Key] = $Request.Query.$Key
                }
            }

            $ManualPagination = $Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)
            $FetchAll = $Request.Query.fetchAll -and [System.Convert]::ToBoolean($Request.Query.fetchAll)
            $ApplyDefaultDate = -not $Input.messageId

            $Query = Build-CIPPQuarantineQueryParams -QueryInput $Input -ApplyDefaultDateRange:$ApplyDefaultDate
            $PageSize = $Query.CmdParams.PageSize

            if ($ManualPagination -or -not $FetchAll) {
                $PageResult = Get-CippQuarantinePagedResults -TenantId $TenantFilter -Query $Query -NextLink $Request.Query.nextLink -TargetPageSize $PageSize
                $Metadata = $PageResult.Metadata
                $PageResult.Results
            } elseif ($FetchAll) {
                $Page = 1
                $AllMessages = [System.Collections.Generic.List[object]]::new()
                do {
                    $Query.CmdParams.Page = $Page
                    $Results = @(Invoke-CippQuarantineExoRequest -TenantId $TenantFilter -Cmdlet 'Get-QuarantineMessage' -CmdParams $Query.CmdParams |
                        Select-Object -ExcludeProperty *data.type*)
                    if ($Results) { $AllMessages.AddRange(@($Results)) }
                    $Page++
                } while (@($Results).Count -eq $PageSize -and $Page -le 1000)
                $Filtered = Apply-CippQuarantinePostFilters -Messages $AllMessages -PostFilters $Query.PostFilters
                $Metadata = [PSCustomObject]@{
                    appliedFilters              = $Query.AppliedFilters
                    fetchAll                    = $true
                    HasPostFilters              = ($Query.PostFilters.Count -gt 0)
                    RawRowsScanned              = $AllMessages.Count
                    FilteredRowsReturned        = @($Filtered).Count
                    PostFilterPaginationLimited = $false
                }
                $Filtered
            }
        } else {
            $Table = Get-CIPPTable -TableName cacheQuarantineMessages
            $PartitionKey = 'QuarantineMessage'
            $30MinutesAgo = (Get-Date).AddMinutes(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Filter = "PartitionKey eq '$PartitionKey' and Timestamp gt datetime'$30MinutesAgo'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Get-CIPPQueueData -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
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
                $Messages = $Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
                foreach ($message in $Messages) {
                    $messageObj = $message.QuarantineMessage | ConvertFrom-Json
                    $messageObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $message.Tenant -Force
                    $messageObj
                }
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        # Only report 403 for actual authorization failures; throttling and other
        # transient errors were previously mislabelled as Forbidden, which stops
        # clients and monitoring from treating them as retryable.
        $StatusCode = if ($ErrorMessage -match 'not authorized|access.*denied|unauthorized|permission') {
            [HttpStatusCode]::Forbidden
        } else {
            [HttpStatusCode]::InternalServerError
        }
        $GraphRequest = $ErrorMessage
        $Metadata = $null
    }

    if ($null -eq $body) {
        if ($StatusCode -eq [HttpStatusCode]::OK) {
            $body = [PSCustomObject]@{
                Results  = @($GraphRequest | Where-Object { $_.Identity -ne $null } | ConvertTo-CippQuarantineDisplayObject | Sort-Object -Property ReceivedTime -Descending)
                Metadata = $Metadata
            }
        } else {
            $body = [PSCustomObject]@{
                Results  = $GraphRequest
                Metadata = $Metadata
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
