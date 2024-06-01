using namespace System.Net

Function Invoke-ExecUpdateSecureScore {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Body = @{
        comment           = $request.body.reason
        state             = $request.body.resolutionType
        vendorInformation = $request.body.vendorInformation
    }
    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/security/secureScoreControlProfiles/$($Request.body.ControlName)" -tenantid $Request.body.TenantFilter -type PATCH -Body $($Body | ConvertTo-Json -Compress)
        $Results = [pscustomobject]@{'Results' = "Succesfully set control to $($body.state) " }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to set Control to $($body.state) $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
