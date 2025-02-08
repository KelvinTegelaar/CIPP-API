using namespace System.Net

Function Invoke-AddBPATemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$($Request.body | ConvertTo-Json -Depth 10)"
            RowKey       = $Request.body.name
            PartitionKey = 'BPATemplate'
            GUID         = $Request.body.name
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created BPA named $($Request.body.name)" -Sev 'Debug'

        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "BPA Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "BPA Template Creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
