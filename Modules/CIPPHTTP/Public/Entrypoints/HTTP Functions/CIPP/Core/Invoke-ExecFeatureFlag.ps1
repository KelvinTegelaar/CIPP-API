function Invoke-ExecFeatureFlag {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Body.Action
    $Id = $Request.Body.Id
    $Enabled = $Request.Body.Enabled

    $ValidationError = switch ($Action) {
        'Set' {
            if ([string]::IsNullOrEmpty($Id)) { 'Feature flag Id is required' }
            elseif ($null -eq $Enabled) { 'Enabled state is required' }
        }
        'Get' {}
        default { "Invalid action: $Action. Valid actions are 'Set' or 'Get'" }
    }
    if ($ValidationError) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ error = $ValidationError }
        }
    }

    try {
        Write-LogMessage -API 'ExecFeatureFlag' -message "Processing feature flag action: $Action for $Id" -sev 'Info'

        switch ($Action) {
            'Set' {
                # Use Set-CIPPFeatureFlag to update the flag
                $Result = Set-CIPPFeatureFlag -Id $Id -Enabled ([bool]$Enabled)

                if ($Result) {
                    Write-LogMessage -API 'ExecFeatureFlag' -message "Successfully updated feature flag $Id to $Enabled" -sev 'Info'
                    $StatusCode = [HttpStatusCode]::OK
                    $Body = @{
                        Results = "Successfully updated feature flag '$Id' to Enabled=$Enabled"
                    }
                } else {
                    throw "Failed to update feature flag '$Id'"
                }
            }
            'Get' {
                if ([string]::IsNullOrEmpty($Id)) {
                    # Get all flags
                    $Flags = Get-CIPPFeatureFlag
                } else {
                    # Get specific flag
                    $Flags = Get-CIPPFeatureFlag -Id $Id
                }

                $StatusCode = [HttpStatusCode]::OK
                $Body = $Flags
            }
        }
    } catch {
        Write-LogMessage -API 'ExecFeatureFlag' -message "Failed to process feature flag: $($_.Exception.Message)" -sev 'Error'
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
