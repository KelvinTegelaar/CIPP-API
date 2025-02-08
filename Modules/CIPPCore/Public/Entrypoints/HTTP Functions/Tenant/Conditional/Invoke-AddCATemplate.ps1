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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.TenantFilter
    try {
        $GUID = (New-Guid).GUID
        $JSON = New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $request.body
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'CATemplate'
            GUID         = "$GUID"
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created CA Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
        $body = [pscustomobject]@{'Results' = 'Successfully added template' }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to create CA Template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Intune Template Deployment failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
