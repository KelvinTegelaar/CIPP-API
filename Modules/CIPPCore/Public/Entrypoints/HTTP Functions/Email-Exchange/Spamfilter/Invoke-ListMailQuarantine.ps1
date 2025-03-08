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
            $Filter = "PartitionKey eq 'QuarantineMessage'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-30)
            if (!$Rows) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Mail Quarantine - All Tenants' -TotalTasks ($TenantList | Measure-Object).Count
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
