function Invoke-ExecDurableFunctions {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Request, $TriggerMetadata)

    $APIName = 'ExecDurableStats'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Collect info
    $StorageContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
    $FunctionName = $env:WEBSITE_SITE_NAME

    # Get orchestrators
    $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f $FunctionName)
    $Yesterday = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "CreatedTime ge datetime'$Yesterday' or RuntimeStatus eq 'Pending' or RuntimeStatus eq 'Running'"
    $Instances = Get-CippAzDataTableEntity @InstancesTable -Filter $Filter

    switch ($Request.Query.Action) {
        'ListOrchestrators' {
            $Orchestrators = foreach ($Instance in $Instances) {
                $Json = $Instance.Input -replace '^"(.+)"$', '$1' -replace '\\"', '"'
                if (Test-Json -Json $Json -ErrorAction SilentlyContinue) {
                    $Instance.Input = $Json | ConvertFrom-Json
                } else {
                    $Instance.Input = 'No Input'
                }
                $Instance
            }

            $Body = [PSCustomObject]@{
                Orchestrators = @($Orchestrators)
            }
        }
        'ListStats' {
            $OrchestratorsByStatus = $Instances | Group-Object -Property RuntimeStatus

            if ($OrchestratorsByStatus.Name -contains 'Pending') {
                $PendingOrchestrators = $OrchestratorsByStatus | Where-Object -Property Name -EQ 'Pending' | Select-Object -ExpandProperty Group
                $Pending30MinCount = $PendingOrchestrators | Where-Object { $_.CreatedTime -lt (Get-Date).AddMinutes(-30).ToUniversalTime() } | Measure-Object | Select-Object -ExpandProperty Count
            }

            $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount

            $Body = [PSCustomObject]@{
                Orchestrators     = @($OrchestratorsByStatus | Select-Object Count, Name)
                Pending30MinCount = $Pending30MinCount ?? 0
                Queues            = @($Queues)
            }
        }
        'ResetDurables' {
            try {
                $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount
                $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
                foreach ($Queue in $RunningQueues) {
                    Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
                    if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
                        $Queue.QueueClient.ClearMessagesAsync()
                    }
                }
                $RunningInstances = $Instances | Where-Object { $_.RuntimeStatus -eq 'Running' -or $_.RuntimeStatus -eq 'Pending' }
                if (($RunningInstances | Measure-Object).Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess('Orchestrators', 'Mark Failed')) {
                        foreach ($Instance in $RunningInstances) {
                            $Instance.RuntimeStatus = 'Failed'
                            Update-AzDataTableEntity @InstancesTable -Entity $Instance
                        }
                    }
                }
                $BlobContainer = '{0}-largemessages' -f $Function.Name
                if (Get-AzStorageContainer -Name $BlobContainer -Context $StorageContext -ErrorAction SilentlyContinue) {
                    Write-Information "- Removing blob container: $BlobContainer"
                    if ($PSCmdlet.ShouldProcess($BlobContainer, 'Remove Blob Container')) {
                        Remove-AzStorageContainer -Name $BlobContainer -Context $StorageContext -Confirm:$false -Force
                    }
                }
                $Body = [PSCustomObject]@{
                    Message = 'Durable functions reset successfully'
                }
            } catch {
                $Body = [PSCustomObject]@{
                    Message = "Error resetting durables: $($_.Exception.Message)"
                }
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}