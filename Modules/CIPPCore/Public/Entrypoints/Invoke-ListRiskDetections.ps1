using namespace System.Net

Function Invoke-ListRiskDetections {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        IdentityRiskEvent.ReadWrite.All
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.TenantFilter

    try {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Retrieved risk detections' -Sev 'Debug' -tenant $TenantFilter

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identityProtection/riskDetections" -tenantid $TenantFilter
        $response = $GraphRequest | Select-Object *,
        @{l = 'locationcipp'; e = { "$($_.location.city) - $($_.location.countryOrRegion)" } }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($response)
            })
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve Risk Detections: $ErrorMessage" -Sev 'Error' -tenant $TenantFilter
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $ErrorMessage
            })
    }
}
