function Invoke-ExecBECCheck {
    <#
    .SYNOPSIS
    Check for Business Email Compromise (BEC) indicators for a user
    
    .DESCRIPTION
    Checks for Business Email Compromise (BEC) indicators for a specified user by querying cached results or initiating a new BEC analysis run. Supports both checking existing results and triggering new analysis.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    
    .NOTES
    Group: Security
    Summary: Exec BEC Check
    Description: Checks for Business Email Compromise (BEC) indicators for a specified user by querying cached results or initiating a new BEC analysis run. Supports both checking existing results and triggering new analysis with orchestration.
    Tags: Security,BEC,Business Email Compromise,Threat Detection
    Parameter: userid (string) [query] - User ID to check for BEC indicators
    Parameter: GUID (string) [query] - GUID for checking specific results
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Parameter: userName (string) [query] - User name for logging
    Parameter: overwrite (bool) [query] - Whether to overwrite existing results and run new analysis
    Response: Returns different response objects based on the scenario:
    Response: - New analysis: { "GUID": "user-id" }
    Response: - Waiting for results: { "Waiting": true }
    Response: - Existing results: BEC analysis results object
    Example: {
      "GUID": "12345678-1234-1234-1234-123456789012"
    }
    Error: Returns error details if the operation fails to check or initiate BEC analysis.
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
            'TenantFilter' = $Request.Query.tenantFilter
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
        $null = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ( ConvertTo-Json -InputObject $InputObject -Depth 5 -Compress )

        @{ GUID = $Request.Query.userid }
    }
    else {
        if (!$Request.Query.GUID) {
            @{ GUID = $Request.Query.userid }
        }
        else {
            if (!$JSONOutput -or $JSONOutput.Status -eq 'Waiting') {
                @{ Waiting = $true }
            }
            else {
                $JSONOutput.Results
            }
        }
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
