function Invoke-ListLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $QueueId = $Request.Query.QueueId
    $Metadata = @{}

    if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
    } else {
        $Table = Get-CIPPTable -TableName cachelicenses

        if ($QueueId) {
            $Filter = "QueueId eq '{0}'" -f $QueueId
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        } else {
            $Timestamp = (Get-Date).AddHours(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
            $Filter = "Timestamp ge datetime'{0}'" -f $Timestamp
            $Tenants = Get-Tenants -IncludeErrors
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.RowKey -in $Tenants.defaultDomainName }
        }

        if ($Rows) {
            $GraphRequest = $Rows | ForEach-Object {
                $LicenseData = $_.License | ConvertFrom-Json -ErrorAction SilentlyContinue
                foreach ($License in $LicenseData) {
                    $License
                }
            }
        } else {
            $QueueReference = 'AllTenants-Licenses'
            $RunningQueue = Get-CIPPQueueData -Reference $QueueReference | Where-Object { $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' -and $_.Reference -eq $QueueReference }

            if ($RunningQueue) {
                $Metadata.Queued = $true
                $Metadata.QueueMessage = 'Data still processing, please wait'
                $Metadata.QueueId = $RunningQueue.RowKey
                $GraphRequest = @()
            } else {
                $TenantList = Get-Tenants -IncludeErrors
                if (($TenantList | Measure-Object).Count -gt 0) {
                    $Queue = New-CippQueueEntry -Name 'Licenses (All Tenants)' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                    $TenantList = $TenantList | Select-Object customerId, defaultDomainName, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'ListLicensesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'ListLicensesOrchestrator'
                        Batch            = @($TenantList)
                        SkipLog          = $true
                    }
                    $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
                    Write-Host "Started licenses orchestration with ID = '$InstanceId'"

                    $Metadata.Queued = $true
                    $Metadata.QueueMessage = 'Loading data for all tenants. Please check back after the job completes'
                    $Metadata.QueueId = $Queue.RowKey
                }
                $GraphRequest = @()
            }
        }
    }

    $Body = [PSCustomObject]@{
        Results  = @($GraphRequest)
        Metadata = $Metadata
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
