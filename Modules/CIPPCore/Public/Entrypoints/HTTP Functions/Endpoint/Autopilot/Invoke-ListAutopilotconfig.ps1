function Invoke-ListAutopilotconfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ($Request.Query.type -eq 'ApProfile') {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$expand=assignments" -tenantid $TenantFilter
        }

        if ($Request.Query.type -eq 'ESP') {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments" -tenantid $TenantFilter |
                Where-Object -Property '@odata.type' -EQ '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
