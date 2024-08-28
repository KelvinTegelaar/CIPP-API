Function Invoke-ExecBECCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $body = if ($request.query.GUID) {
        $Table = Get-CippTable -tablename 'cachebec'
        $Filter = "PartitionKey eq 'bec' and RowKey eq '$($request.query.GUID)'"
        $JSONOutput = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if (!$JSONOutput -or $JSONOutput.Status -eq 'Waiting') {
            @{ Waiting = $true }
        } else {
            $JSONOutput.Results
        }
    } else {
        $Batch = @{
            'FunctionName' = 'BECRun'
            'UserID'       = $Request.Query.userid
            'TenantFilter' = $Request.Query.tenantfilter
            'userName'     = $Request.Query.userName
        }

        $Table = Get-CippTable -tablename 'cachebec'

        $Entity = @{
            UserId       = $Request.Query.userid
            Results      = ''
            RowKey       = $Request.Query.userid
            Status       = 'Waiting'
            PartitionKey = 'bec'
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'BECRunOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }
        #Write-Host ($InputObject | ConvertTo-Json)
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

        @{ GUID = $Request.Query.userid }
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
