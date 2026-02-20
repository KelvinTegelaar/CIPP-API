function Invoke-ListFeatureFlags {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        Write-LogMessage -API 'ListFeatureFlags' -message 'Accessed feature flags list' -sev 'Debug'

        $FeatureFlags = Get-CIPPFeatureFlag

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($FeatureFlags)
    } catch {
        Write-LogMessage -API 'ListFeatureFlags' -message "Failed to retrieve feature flags: $($_.Exception.Message)" -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{
            error   = $_.Exception.Message
            details = $_.Exception
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
