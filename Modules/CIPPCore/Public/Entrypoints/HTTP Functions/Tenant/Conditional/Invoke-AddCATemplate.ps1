using namespace System.Net

Function Invoke-AddCATemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Name = $Request.Body.name
    try {
        $GUID = (New-Guid).GUID
        $JSON = New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $Request.Body
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'CATemplate'
            GUID         = "$GUID"
        }
        $Result = "Created CA Template $($Name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message "Created CA Template $($Name) with GUID $GUID" -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create CA Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to create CA Template: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })

}
