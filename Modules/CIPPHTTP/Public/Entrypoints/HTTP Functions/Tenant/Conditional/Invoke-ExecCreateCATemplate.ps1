function Invoke-ExecCreateCATemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Body = $Request.Body
        $DisplayName = $Body.displayName ?? $Body.name
        if ([string]::IsNullOrWhiteSpace($DisplayName)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: displayName is required' }
            }
        }

        $GUID = (New-Guid).GUID

        # Strip any read-only or internal properties before storing
        $Template = $Body | Select-Object -Property * -ExcludeProperty GUID, id, createdDateTime, modifiedDateTime, templateId

        $JSON = ConvertTo-Json -InputObject $Template -Depth 100 -Compress

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'CATemplate'
            GUID         = "$GUID"
        }

        $Result = "Successfully created CA template '$DisplayName' with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create CA template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
