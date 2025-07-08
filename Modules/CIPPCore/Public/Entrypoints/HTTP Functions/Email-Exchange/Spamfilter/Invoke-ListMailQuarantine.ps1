function Invoke-ListMailQuarantine {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ 'PageSize' = 1000 } | Select-Object -ExcludeProperty *data.type*
        } else {
            $Table = Get-CIPPTable -TableName cacheQuarantineMessages
            $PartitionKey = 'QuarantineMessage'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-30)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                }
                [PSCustomObject]@{
                    Waiting = $true
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Mail Quarantine - All Tenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
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
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                [PSCustomObject]@{
                    Waiting = $true
                }
            } else {
                $messages = $Rows
                foreach ($message in $messages) {
                    $messageObj = $message.QuarantineMessage | ConvertFrom-Json
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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
