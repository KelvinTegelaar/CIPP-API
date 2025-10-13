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
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    try {
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $env:TenantID -type POST -Body "{ `"appId`": `"2832473f-ec63-45fb-976f-5d45a7d4bb91`" }" -NoAuthCheck $true
        $Result = "Successfully completed request. Add your GDAP migration permissions to your SAM application here: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$($env:ApplicationID)/isMSAApp/ "
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add SPN. The error was: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $env:TenantID -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
