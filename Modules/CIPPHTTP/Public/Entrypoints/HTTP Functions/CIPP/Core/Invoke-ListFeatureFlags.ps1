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

        $FeatureFlags = @(Get-CIPPFeatureFlag)

        # Environment-driven overrides: enable flags that depend on the runtime platform
        if ($env:CIPPNG -eq 'true') {
            foreach ($Flag in $FeatureFlags) {
                if ($Flag.Id -eq 'SuperAdminNG') {
                    $Flag.Enabled = $true
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = $FeatureFlags
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
