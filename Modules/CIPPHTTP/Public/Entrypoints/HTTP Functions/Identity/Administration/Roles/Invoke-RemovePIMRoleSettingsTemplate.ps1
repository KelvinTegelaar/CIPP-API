function Invoke-RemovePIMRoleSettingsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.ReadWrite
    .SYNOPSIS
        Delete a PIM role settings template.
    .DESCRIPTION
        Deletes a saved Privileged Identity Management role settings template by GUID. Tenants already configured from the template keep their settings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        # GUID of the template to delete.
        $ID = $Request.Query.ID ?? $Request.Body.ID ?? $Request.Body.GUID
        if ([string]::IsNullOrWhiteSpace($ID)) { throw 'ID is required' }

        $Table = Get-CippTable -tablename 'templates'
        $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type String
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'PIMRoleSettingsTemplate' and RowKey eq '$SafeID'"

        if ($Template) {
            Remove-CIPPAzDataTableEntity @Table -Entity $Template
            $Result = "Successfully deleted PIM role settings template with ID: $ID"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $Result = "PIM role settings template with ID $ID not found"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Warning'
            $StatusCode = [HttpStatusCode]::NotFound
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete PIM role settings template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = "$Result" }
    }
}
