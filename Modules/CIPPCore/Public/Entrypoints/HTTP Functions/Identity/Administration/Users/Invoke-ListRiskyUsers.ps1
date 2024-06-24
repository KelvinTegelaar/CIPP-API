using namespace System.Net

Function Invoke-ListRiskyUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        IdentityRiskyUser.ReadWrite.All
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.TenantFilter

    try {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Retrieved risky users' -Sev 'Debug' -tenant $TenantFilter

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identityProtection/riskyUsers" -tenantid $TenantFilter

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($GraphRequest)
            })
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve risky users: $ErrorMessage" -Sev 'Error' -tenant $TenantFilter
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $ErrorMessage
            })
    }
}
