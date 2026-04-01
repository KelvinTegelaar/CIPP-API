function Invoke-ListSafeAttachmentsFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName CacheSafeAttachmentsFilters
            $PartitionKey = 'SafeAttachmentsFilter'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading safe attachments filters for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Safe Attachments - All Tenants' -Link '/email/reports/safeattachments-filters?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading safe attachments filters for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'SafeAttachmentsFiltersOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListSafeAttachmentsFiltersAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Output = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } else {
            $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentPolicy' | Select-Object -Property *
            $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeAttachmentRule' | Select-Object -Property *

            $Output = $Policies | Select-Object -Property *,
            @{ Name = 'RuleName'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.Name } } } },
            @{ Name = 'Priority'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.Priority } } } },
            @{ Name = 'RecipientDomainIs'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.RecipientDomainIs } } } },
            @{ Name = 'State'; Expression = { foreach ($item in $Rules) { if ($item.SafeAttachmentPolicy -eq $_.Name) { $item.State } } } }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Output = $ErrorMessage
    }

    $Body = [PSCustomObject]@{
        Results  = @($Output | Where-Object { $_.Id -ne $null })
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
