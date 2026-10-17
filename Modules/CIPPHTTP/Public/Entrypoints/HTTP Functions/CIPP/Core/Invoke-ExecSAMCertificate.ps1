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

    $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Get'
    if ($Action -notin @('Get', 'Renew')) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = "Failed to process SAM certificate request: Invalid action: $Action. Valid actions are 'Get' or 'Renew'" }
        }
    }

    try {
        switch ($Action) {
            'Get' {
                $Stored = Get-CIPPSAMCertificate -SkipCache -ErrorAction SilentlyContinue
                if ($null -eq $Stored) {
                    $Body = @{
                        Configured    = $false
                        ApplicationId = $env:ApplicationID
                        Results       = 'No SAM certificate found. One will be created automatically by the weekly token update, or use the Renew action to create it now.'
                    }
                } else {
                    $RegisteredOnApp = $false
                    $Registered = [System.Collections.Generic.List[object]]::new()
                    try {
                        $AppRegistration = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($env:ApplicationID)')?`$select=id,keyCredentials" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                        # Graph returns customKeyIdentifier as the hex thumbprint string, but tolerate base64 as well
                        $Identifiers = @($AppRegistration.keyCredentials.customKeyIdentifier)
                        $RegisteredOnApp = $Identifiers -contains $Stored.Thumbprint -or $Identifiers -contains [Convert]::ToBase64String([Convert]::FromHexString($Stored.Thumbprint))
                        foreach ($Credential in @($AppRegistration.keyCredentials | Where-Object { $_.type -eq 'AsymmetricX509Cert' })) {
                            $KeyId = [string]$Credential.customKeyIdentifier
                            $CredentialThumbprint = $null
                            if ($KeyId -match '^[0-9A-Fa-f]{40}$') {
                                $CredentialThumbprint = $KeyId.ToUpperInvariant()
                            } else {
                                try { $CredentialThumbprint = [Convert]::ToHexString([Convert]::FromBase64String($KeyId)) } catch { $CredentialThumbprint = $null }
                            }
                            $Registered.Add([pscustomobject]@{
                                    DisplayName   = $Credential.displayName
                                    KeyId         = $Credential.keyId
                                    StartDateTime = $Credential.startDateTime
                                    EndDateTime   = $Credential.endDateTime
                                    Thumbprint    = $CredentialThumbprint
                                    ThisInstance  = $null -ne $CredentialThumbprint -and $CredentialThumbprint -eq $Stored.Thumbprint
                                })
                        }
                    } catch {
                        $Registered.Clear()
                        Write-Warning "Could not check app registration key credentials: $($_.Exception.Message)"
                    }
                    $Body = @{
                        Configured      = $true
                        ApplicationId   = $env:ApplicationID
                        Thumbprint      = $Stored.Thumbprint
                        Subject         = $Stored.Certificate.Subject
                        NotBefore       = $Stored.NotBefore
                        NotAfter        = $Stored.NotAfter
                        DaysRemaining   = [math]::Floor(($Stored.NotAfter - (Get-Date).ToUniversalTime()).TotalDays)
                        RegisteredOnApp = $RegisteredOnApp
                        RegisteredCertificates = @($Registered)
                    }
                }
                $StatusCode = [HttpStatusCode]::OK
            }
            'Renew' {
                # Unknown before-state acknowledges nothing, so no unrelated change is mislabelled as CIPP's own.
                $Before = $null
                try { $Before = @((Get-CIPPSAMCredentials).Credentials | ForEach-Object keyId) } catch { }
                $Actor = 'CIPP'
                try { $Actor = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails ?? 'CIPP' } catch { }
                $Result = Update-CIPPSAMCertificate -Force -LogHeaders $Request.Headers -APIName $Request.Params.CIPPEndpoint -ErrorAction Stop
                try {
                    $After = Get-CIPPSAMCredentials
                    $Changed = if ($null -ne $Before) { @(Compare-Object -ReferenceObject $Before -DifferenceObject @($After.Credentials | ForEach-Object keyId) | ForEach-Object InputObject) } else { @() }
                    $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge $Changed -AcknowledgeNote "Certificate renewed by CIPP (manual, by $Actor)." -CredentialState $After
                } catch { Write-Warning "Could not refresh the SAM credential snapshot: $($_.Exception.Message)" }
                $Body = @{
                    Results     = "SAM certificate renewed. Thumbprint: $($Result.Thumbprint), expires: $($Result.NotAfter)"
                    Thumbprint  = $Result.Thumbprint
                    NotAfter    = $Result.NotAfter
                    StorageMode = $Result.StorageMode
                }
                $StatusCode = [HttpStatusCode]::OK
            }
        }
    } catch {
        Write-LogMessage -headers $Request.Headers -API 'ExecSAMCertificate' -tenant 'Global' -message "Failed to process SAM certificate $Action request: $($_.Exception.Message)" -sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{
            Results = "Failed to process SAM certificate request: $($_.Exception.Message)"
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
