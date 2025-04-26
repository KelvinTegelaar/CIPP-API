using namespace System.Net

function Invoke-RemoveStandardTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $ID = $Request.Body.ID ?? $Request.Query.ID
    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, JSON
        $TemplateName = (ConvertFrom-Json -InputObject $ClearRow.JSON).templateName
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        $Result = "Removed Standards Template named: '$($TemplateName)' with id: $($ID)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Standards template: $TemplateName with id: $ID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
