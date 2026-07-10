function Invoke-ListFeatureFlags {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists CIPP feature flags and their enabled/disabled state, including environment-driven overrides.
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
                elseIf ($Flag.Id -eq 'AppInsights') {
                    $Flag.Enabled = $false
                }
                elseIf ($Flag.Id -eq 'FunctionOffloading') {
                    $Flag.Enabled = $false
                }
            }
        }

        # Hosted instances hide the backend settings page (Azure resource URLs)
        if ($env:CIPP_HOSTED -eq 'true') {
            foreach ($Flag in $FeatureFlags) {
                if ($Flag.Id -eq 'BackendSettings') {
                    $Flag.Enabled = $false
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
