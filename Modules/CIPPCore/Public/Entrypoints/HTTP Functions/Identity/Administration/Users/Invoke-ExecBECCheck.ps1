Function Invoke-ExecBECCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'cachebec'

    $UserId = $Request.Query.userid ?? $Request.Query.GUID
    $Filter = "PartitionKey eq 'bec' and RowKey eq '$UserId'"
    $JSONOutput = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    Write-Host ($Request.Query | ConvertTo-Json)

    $body = if (([string]::IsNullOrEmpty($JSONOutput.Results) -and $JSONOutput.Status -ne 'Waiting' ) -or $Request.Query.overwrite -eq $true) {
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
    } else {
        if (!$Request.Query.GUID) {
            @{ GUID = $Request.Query.userid }
        } else {
            if (!$JSONOutput -or $JSONOutput.Status -eq 'Waiting') {
                @{ Waiting = $true }
            } else {
                $JSONOutput.Results
            }
        }
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
