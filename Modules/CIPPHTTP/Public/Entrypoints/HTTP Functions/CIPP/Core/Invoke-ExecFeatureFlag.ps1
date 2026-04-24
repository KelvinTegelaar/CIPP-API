function Invoke-ExecFeatureFlag {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Action = $Request.Body.Action
        $Id = $Request.Body.Id
        $Enabled = $Request.Body.Enabled

        Write-LogMessage -API 'ExecFeatureFlag' -message "Processing feature flag action: $Action for $Id" -sev 'Info'

        switch ($Action) {
            'Set' {
                if ([string]::IsNullOrEmpty($Id)) {
                    throw 'Feature flag Id is required'
                }

                if ($null -eq $Enabled) {
                    throw 'Enabled state is required'
                }

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
            default {
                throw "Invalid action: $Action. Valid actions are 'Set' or 'Get'"
            }
        }
    } catch {
        Write-LogMessage -API 'ExecFeatureFlag' -message "Failed to process feature flag: $($_.Exception.Message)" -sev 'Error'
        $StatusCode = [HttpStatusCode]::BadRequest
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
