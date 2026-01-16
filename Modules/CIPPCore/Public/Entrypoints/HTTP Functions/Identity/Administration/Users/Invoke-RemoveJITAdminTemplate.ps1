function Invoke-RemoveJITAdminTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $ID = $Request.Query.ID ?? $Request.Body.ID
        
        if ([string]::IsNullOrWhiteSpace($ID)) {
            throw 'ID is required'
        }

        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'JITAdminTemplate' and RowKey eq '$ID'"
        $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if ($Template) {
            Remove-AzDataTableEntity @Table -Entity $Template
            $Result = "Successfully deleted JIT Admin Template with ID: $ID"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $Result = "JIT Admin Template with ID $ID not found"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Warning'
            $StatusCode = [HttpStatusCode]::NotFound
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete JIT Admin Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
