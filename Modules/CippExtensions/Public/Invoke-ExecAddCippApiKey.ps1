function Add-CippApiKey {
    # Input bindings are passed in via param block.
    param($Request = $null, $TriggerMetadata)

    if ($Request) {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
    }

    try {
        $ApiKey = New-CippApiKey -Description $Request.Query.Description -AccessLevel $Request.Query.AccessLevel
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $ApiKey
            })
    } catch {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{Results = $_.Exception.Message }
            })
    }

}
