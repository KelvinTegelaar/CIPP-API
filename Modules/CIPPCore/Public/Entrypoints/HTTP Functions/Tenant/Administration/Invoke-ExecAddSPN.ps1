using namespace System.Net

Function Invoke-ExecAddSPN {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Body = if ($Request.Query.Enable) { '{"accountEnabled":"true"}' } else { '{"accountEnabled":"false"}' }
    try {
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $ENV:TenantID -type POST -Body "{ `"appId`": `"2832473f-ec63-45fb-976f-5d45a7d4bb91`" }" -NoAuthCheck $true
        $Results = [pscustomobject]@{'Results' = "Successfully completed request. Add your GDAP migration permissions to your SAM application here: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$($ENV:ApplicationID)/isMSAApp/ " }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to add SPN. Please manually execute 'New-AzureADServicePrincipal -AppId 2832473f-ec63-45fb-976f-5d45a7d4bb91' The error was $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
