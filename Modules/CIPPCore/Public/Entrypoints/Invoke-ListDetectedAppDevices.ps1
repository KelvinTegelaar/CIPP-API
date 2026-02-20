function Invoke-ListDetectedAppDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $AppID = $Request.Query.AppID

    # Get managed devices where a specific detected app is installed
    # Uses deviceManagement/detectedApps/{id}/managedDevices endpoint

    try {
        if (-not $AppID) {
            throw "AppID parameter is required"
        }

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/detectedApps/$AppID/managedDevices" -Tenantid $TenantFilter

        # Ensure we return an array even if null
        if ($null -eq $GraphRequest) {
            $GraphRequest = @()
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::OK
        $GraphRequest = $ErrorMessage
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
