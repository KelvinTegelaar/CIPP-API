    using namespace System.Net

    Function Invoke-ExecGetLocalAdminPassword {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName

try {
    $GraphRequest = Get-CIPPLapsPassword -device $($request.query.guid) -tenantFilter $Request.Query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
    $Body = [pscustomobject]@{"Results" = $GraphRequest }

}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $Body = [pscustomobject]@{"Results" = "Failed. $ErrorMessage" }

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })

    }
