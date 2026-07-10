function Invoke-ExecSAMCertificate {
    <#
    .SYNOPSIS
        Get SAM certificate status or trigger a renewal
    .DESCRIPTION
        Returns status information about the SAM app certificate (thumbprint, validity,
        registration state) or forces a renewal via Update-CIPPSAMCertificate. Never
        returns private key material.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Get'

        switch ($Action) {
            'Get' {
                $Stored = Get-CIPPSAMCertificate -SkipCache -ErrorAction SilentlyContinue
                if ($null -eq $Stored) {
                    $Body = @{
                        Configured = $false
                        Results    = 'No SAM certificate found. One will be created automatically by the weekly token update, or use the Renew action to create it now.'
                    }
                } else {
                    $RegisteredOnApp = $false
                    try {
                        $AppRegistration = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($env:ApplicationID)')?`$select=id,keyCredentials" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                        # Graph returns customKeyIdentifier as the hex thumbprint string, but tolerate base64 as well
                        $Identifiers = @($AppRegistration.keyCredentials.customKeyIdentifier)
                        $RegisteredOnApp = $Identifiers -contains $Stored.Thumbprint -or $Identifiers -contains [Convert]::ToBase64String([Convert]::FromHexString($Stored.Thumbprint))
                    } catch {
                        Write-Warning "Could not check app registration key credentials: $($_.Exception.Message)"
                    }
                    $Body = @{
                        Configured      = $true
                        Thumbprint      = $Stored.Thumbprint
                        NotBefore       = $Stored.NotBefore
                        NotAfter        = $Stored.NotAfter
                        DaysRemaining   = [math]::Floor(($Stored.NotAfter - (Get-Date).ToUniversalTime()).TotalDays)
                        RegisteredOnApp = $RegisteredOnApp
                    }
                }
                $StatusCode = [HttpStatusCode]::OK
            }
            'Renew' {
                $Result = Update-CIPPSAMCertificate -Force -ErrorAction Stop
                $Body = @{
                    Results     = "SAM certificate renewed. Thumbprint: $($Result.Thumbprint), expires: $($Result.NotAfter)"
                    Thumbprint  = $Result.Thumbprint
                    NotAfter    = $Result.NotAfter
                    StorageMode = $Result.StorageMode
                }
                $StatusCode = [HttpStatusCode]::OK
            }
            default {
                throw "Invalid action: $Action. Valid actions are 'Get' or 'Renew'"
            }
        }
    } catch {
        Write-LogMessage -API 'ExecSAMCertificate' -message "Failed to process SAM certificate request: $($_.Exception.Message)" -sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Results = "Failed to process SAM certificate request: $($_.Exception.Message)"
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
