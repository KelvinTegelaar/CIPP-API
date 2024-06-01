using namespace System.Net

Function Invoke-ListAutopilotconfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $userid = $Request.Query.UserID
    try {
        if ($request.query.type -eq 'ApProfile') {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$expand=assignments" -tenantid $TenantFilter
        }

        if ($request.query.type -eq 'ESP') {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments" -tenantid $TenantFilter | Where-Object -Property '@odata.type' -EQ '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
