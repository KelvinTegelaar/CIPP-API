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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Body = @{
        comment           = $request.body.reason
        state             = $request.body.resolutionType.value
        vendorInformation = $request.body.vendorInformation
    }
    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/security/secureScoreControlProfiles/$($Request.body.ControlName)" -tenantid $Request.body.TenantFilter -type PATCH -Body $($Body | ConvertTo-Json -Compress)
        $Results = [pscustomobject]@{'Results' = "Successfully set control to $($Body.state) " }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to set Control to $($Body.state) $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
