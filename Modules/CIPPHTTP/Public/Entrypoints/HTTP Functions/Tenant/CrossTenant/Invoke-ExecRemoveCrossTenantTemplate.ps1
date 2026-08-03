function Invoke-ExecRemoveCrossTenantTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.CrossTenant.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $GUID = $Request.Body.GUID ?? $Request.Query.GUID
        if ([string]::IsNullOrWhiteSpace($GUID)) {
            throw 'Template GUID is required.'
        }

        $Table = Get-CippTable -tablename 'templates'
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CrossTenantTemplate' and RowKey eq '$GUID'"

        if (-not $Entity) {
            throw "Template with GUID $GUID not found."
        }

        Remove-CIPPAzDataTableEntity @Table -Entity $Entity

        Write-LogMessage -headers $Headers -API $APIName -message "Cross-tenant security template with GUID $GUID removed." -Sev 'Info'

        $Body = [PSCustomObject]@{
            Results = 'Successfully removed cross-tenant security template.'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove cross-tenant template: $ErrorMessage" -Sev 'Error'
        $Body = [PSCustomObject]@{
            Results = "Failed to remove cross-tenant template: $ErrorMessage"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
