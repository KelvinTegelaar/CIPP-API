using namespace System.Net

Function Invoke-AddStandardsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $GUID = $Request.body.GUID ? $request.body.GUID : (New-Guid).GUID
    $JSON = (ConvertTo-Json -Depth 100 -InputObject ($Request.body))
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = 'StandardsTemplate'
        GUID         = "$GUID"
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created CA Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
    $body = [pscustomobject]@{'Results' = 'Successfully added template' }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
