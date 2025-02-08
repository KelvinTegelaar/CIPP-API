using namespace System.Net

Function Invoke-ExecRestoreDeleted {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter

    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($Request.query.ID)/restore" -tenantid $TenantFilter -type POST -body '{}' -verbose
        $Results = [pscustomobject]@{'Results' = 'Successfully completed request.' }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
