function Invoke-RemoveIntuneReusableSettingTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $ID = $Request.Query.ID ?? $Request.Body.ID

    try {
        if (-not $ID) { throw 'You must supply an ID' }

        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'IntuneReusableSettingTemplate' and RowKey eq '$ID'"
        $Row = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $Row

        $Result = "Removed Intune reusable setting template with ID $ID"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove Intune reusable setting template $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
