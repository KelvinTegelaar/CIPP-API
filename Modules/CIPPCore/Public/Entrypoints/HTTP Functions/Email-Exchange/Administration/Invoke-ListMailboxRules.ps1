using namespace System.Net

Function Invoke-ListMailboxRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    $Table = Get-CIPPTable -TableName cachembxrules
    if ($TenantFilter -ne 'AllTenants') {
        $Table.Filter = "Tenant eq '$TenantFilter'"
    }
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
    $PartitionKey = 'MailboxRules'
    $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
    $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }

    $Metadata = @{}
    # If a queue is running, we will not start a new one
    if ($RunningQueue) {
        $Metadata = [PSCustomObject]@{
            QueueMessage = "Still loading data for $TenantFilter. Please check back in a few more minutes"
        }
        [PSCustomObject]@{
            Waiting = $true
        }
    } elseif ((!$Rows -and !$RunningQueue) -or ($TenantFilter -eq 'AllTenants' -and ($Rows | Measure-Object).Count -eq 1)) {
        # If no rows are found and no queue is running, we will start a new one
        $Metadata = [PSCustomObject]@{
            QueueMessage = "Loading data for $TenantFilter. Please check back in 1 minute"
        }

        if ($TenantFilter -eq 'AllTenants') {
            $Tenants = Get-Tenants -IncludeErrors | Select-Object defaultDomainName
            $Type = 'All Tenants'
        } else {
            $Tenants = @(@{ defaultDomainName = $TenantFilter })
            $Type = $TenantFilter
        }
        $Queue = New-CippQueueEntry -Name "Mailbox Rules ($Type)" -Reference $QueueReference -TotalTasks ($Tenants | Measure-Object).Count
        $Batch = $Tenants | Select-Object defaultDomainName, @{Name = 'FunctionName'; Expression = { 'ListMailboxRulesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }
        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'ListMailboxRulesOrchestrator'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            #Write-Host ($InputObject | ConvertTo-Json)
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            Write-Host "Started mailbox rules orchestration with ID = '$InstanceId'"
        }

    } else {
        if ($TenantFilter -ne 'AllTenants') {
            $Rows = $Rows | Where-Object -Property Tenant -EQ $TenantFilter
            $Rows = $Rows
        }
        $GraphRequest = $Rows | ForEach-Object {
            $NewObj = $_.Rules | ConvertFrom-Json -ErrorAction SilentlyContinue
            $NewObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $_.Tenant -Force
            $NewObj
        }
    }

    # If no results are found, we will return an empty message to prevent null reference errors in the frontend
    $GraphRequest = $GraphRequest ?? @()
    $Body = @{
        Results  = @($GraphRequest)
        Metadata = $Metadata
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
