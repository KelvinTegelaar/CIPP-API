function Invoke-ExecSAMCredentials {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Health and management of the CIPP-SAM application's secrets, certificates and refresh tokens.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Status'
    $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $IsDevMode = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'
    $HasSecret = $env:ApplicationSecret -and $env:ApplicationSecret -notmatch $PlaceholderPattern
    $ConfigTable = Get-CIPPTable -tablename 'Config'

    # Key Vault timestamps only; the DevSecrets table keeps none.
    $GetSecretUpdated = {
        param([string]$Name)
        if ($IsDevMode) { return $null }
        try { (Get-CippKeyVaultSecret -Name $Name -IncludeAttributes -ErrorAction Stop).Updated } catch { $null }
    }

    switch ($Action) {
        'Status' {
            try {
                if (-not $env:ApplicationID -or $env:ApplicationID -match $PlaceholderPattern) {
                    $Body = @{ Results = @{ overall = 'notConfigured'; storedSecret = @{ state = 'notConfigured' }; credentials = @() } }
                    break
                }

                $CredentialsError = $null
                try {
                    $State = Get-CIPPSAMCredentials
                } catch {
                    $CredentialsError = (Get-CippException -Exception $_).NormalizedError
                    $State = [pscustomobject]@{ Credentials = @(); OwnSecretKeyId = ''; OwnThumbprint = ''; StoredCertificate = $null }
                    try { $State.StoredCertificate = Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop; $State.OwnThumbprint = $State.StoredCertificate.Thumbprint } catch { }
                }
                $Credentials = @($State.Credentials)
                $Now = (Get-Date).ToUniversalTime()
                $SoonCutoff = $Now.AddDays(30)

                $TenantDomain = $null
                try {
                    $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization?$select=verifiedDomains' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
                    $TenantDomain = (@($Org.verifiedDomains) | Where-Object { $_.isDefault } | Select-Object -First 1).name
                } catch { }

                # The flag is the source of truth; the env mirror is per runspace and goes stale after a toggle.
                $CertFlagEnabled = $env:CertificateAuthMode
                try { $CertFlagEnabled = (Get-CIPPFeatureFlag -Id 'CertificateAuthentication').Enabled -eq $true } catch { }
                $AuthMode = if ($CertFlagEnabled) { 'certificate' } else { 'secret' }

                $OwnSecret = if ($State.OwnSecretKeyId) { $Credentials | Where-Object { $_.type -eq 'Secret' -and $_.keyId -eq $State.OwnSecretKeyId } | Select-Object -First 1 }
                if (-not $HasSecret) {
                    $StoredSecret = @{ state = 'none'; message = 'No client secret is stored.' }
                } else {
                    # Include the refresh grant: that is the hot path, and Entra activates it later than client_credentials.
                    $Probe = Test-CIPPSAMSecret -IncludeRefreshGrant
                    $SecretState = switch ($Probe.reason) { 'ready' { 'valid' } 'propagating' { 'propagating' } 'notConfigured' { 'notConfigured' } default { 'error' } }
                    $StoredSecret = @{ state = $SecretState; message = $Probe.message }
                }
                $StoredSecret.keyId = $State.OwnSecretKeyId
                $StoredSecret.expires = $OwnSecret.endDateTime

                $Cert = $State.StoredCertificate
                $Certificate = @{
                    configured      = [bool]$Cert
                    thumbprint      = $Cert.Thumbprint
                    notAfter        = $Cert.NotAfter
                    registeredOnApp = [bool]($Cert -and ($Credentials | Where-Object { $_.type -eq 'Certificate' -and $_.thumbprint -eq $Cert.Thumbprint }))
                }

                $PartnerToken = @{ updated = & $GetSecretUpdated 'RefreshToken' }
                try {
                    # Bypass the shared cache so a stale cached failure cannot masquerade as a dead token.
                    $null = Get-GraphToken -ReturnRefresh $true -SkipCache $true -ErrorAction Stop
                    $PartnerToken.state = 'valid'
                } catch {
                    $PartnerToken.state = 'error'
                    $PartnerToken.message = $_.Exception.Message
                }

                $DirectTenants = [System.Collections.Generic.List[object]]::new()
                foreach ($Tenant in @(Get-Tenants -IncludeAll | Where-Object { $_.Excluded -eq $false -and $_.delegatedPrivilegeStatus -eq 'directTenant' })) {
                    $Entry = @{
                        customerId        = $Tenant.customerId
                        displayName       = $Tenant.displayName
                        defaultDomainName = $Tenant.defaultDomainName
                        updated           = & $GetSecretUpdated $Tenant.customerId
                    }
                    try {
                        $null = Get-GraphToken -ReturnRefresh $true -TenantId $Tenant.customerId -SkipCache $true -ErrorAction Stop
                        $Entry.state = 'valid'
                    } catch {
                        $Entry.state = 'error'
                        $Entry.message = $_.Exception.Message
                    }
                    $DirectTenants.Add($Entry)
                }

                $Results = @{
                    applicationId       = $env:ApplicationID
                    tenantId            = $env:TenantID
                    tenantDomain        = $TenantDomain
                    authMode            = $AuthMode
                    storedSecret        = $StoredSecret
                    certificate         = $Certificate
                    credentials         = $Credentials
                    credentialsError    = $CredentialsError
                    partnerRefreshToken = $PartnerToken
                    directTenants       = @($DirectTenants)
                }


                # Rollback secrets are not rotated in certificate mode, so only the active credential counts.
                $SecretExpiring = $AuthMode -eq 'secret' -and $OwnSecret -and ([datetime]$OwnSecret.endDateTime).ToUniversalTime() -lt $SoonCutoff
                $CertExpiring = $Cert -and ([datetime]$Cert.NotAfter).ToUniversalTime() -lt $SoonCutoff
                $TokenFailing = $PartnerToken.state -eq 'error' -or ($DirectTenants | Where-Object { $_.state -eq 'error' }) -or
                ($AuthMode -eq 'secret' -and $StoredSecret.state -in @('error', 'none')) -or ($AuthMode -eq 'certificate' -and -not $Certificate.registeredOnApp)
                $Unreviewed = $Credentials | Where-Object { $_.owner -ne 'thisInstance' -and -not $_.known }
                $Results.overall = if ($TokenFailing) { 'tokenFailing' } elseif ($SecretExpiring -or $CertExpiring) { 'secretExpiring' } elseif ($Unreviewed) { 'unreviewedCredentials' } else { 'healthy' }

                $Body = @{ Results = $Results }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Failed to get SAM credential status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Failed to get SAM credential status: $($ErrorMessage.NormalizedError)" }
            }
        }

        'RotateSecret' {
            if (-not $HasSecret) {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Body = @{ Results = 'This instance has no client secret to rotate. It authenticates with the SAM certificate only.' }
                break
            }
            try {
                $Rotated = Update-CIPPSAMSecret -DisplayName 'UpdateTokens' -Source 'Manual' -Headers $Headers -APIName $APIName
                $null = Clear-CippTokenCache
                $Body = @{
                    Results = @{
                        message  = "Created a new client secret (keyId $($Rotated.KeyId), expires $($Rotated.EndDateTime)). Microsoft can take several minutes to activate it, sometimes 10 to 15; token requests may fail with AADSTS7000215 until then."
                        severity = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Secret rotation failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'RevokeCredential' {
            $KeyId = [string]$Request.Body.keyId
            if ($KeyId -notmatch $GuidPattern) {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Body = @{ Results = 'A valid credential keyId is required.' }
                break
            }
            try {
                $State = Get-CIPPSAMCredentials
                $Credential = $State.Credentials | Where-Object { $_.keyId -eq $KeyId } | Select-Object -First 1
                if (-not $Credential) {
                    $StatusCode = [HttpStatusCode]::NotFound
                    $Body = @{ Results = "No credential with keyId $KeyId exists on the CIPP-SAM application." }
                    break
                }
                if ($Credential.owner -eq 'thisInstance') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'This credential is the one this CIPP instance signs in with and cannot be revoked here. Rotate it instead.' }
                    break
                }
                if ($Credential.type -eq 'Secret') {
                    New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/applications/$($State.AppObjectId)/removePassword" -Body (ConvertTo-Json -Compress -InputObject @{ keyId = $KeyId }) -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                } else {
                    # Same whole-collection PATCH Update-CIPPSAMCertificate uses; removeKey would need a proof-of-possession token.
                    $Remaining = @($State.KeyCredentials | Where-Object { $_.keyId -ne $KeyId })
                    New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($State.AppObjectId)" -Body (ConvertTo-Json -Compress -Depth 10 -InputObject @{ keyCredentials = $Remaining }) -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                }
                $Flag = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'SAMCredential' and RowKey eq '$KeyId'"
                if ($Flag) { Remove-AzDataTableEntity @ConfigTable -Entity $Flag -Force }
                $Identifier = if ($Credential.thumbprint) { "thumbprint $($Credential.thumbprint)" } else { "keyId $KeyId" }
                $Actor = 'CIPP'
                try { $Actor = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails ?? 'CIPP' } catch { }
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Manual revoke by $Actor`: revoked CIPP-SAM $($Credential.type.ToLower()) '$($Credential.displayName)' ($Identifier, owner $($Credential.owner))." -sev Alert
                try { $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge $KeyId -AcknowledgeNote "Revoked by CIPP (manual, by $Actor)." } catch { Write-Information "Could not refresh the SAM credential snapshot: $($_.Exception.Message)" }
                $Body = @{ Results = @{ message = "Revoked $($Credential.type.ToLower()) '$($Credential.displayName)'."; severity = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Failed to revoke CIPP-SAM credential keyId $KeyId`: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Failed to revoke the credential: $($ErrorMessage.NormalizedError)" }
            }
        }

        'FlagCredential' {
            $KeyId = [string]$Request.Body.keyId
            $Label = ([string]$Request.Body.label).Trim()
            if ($KeyId -notmatch $GuidPattern -or -not $Label) {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Body = @{ Results = 'A credential keyId and a label are required.' }
                break
            }
            try {
                if (-not ((Get-CIPPSAMCredentials).Credentials | Where-Object { $_.keyId -eq $KeyId })) {
                    $StatusCode = [HttpStatusCode]::NotFound
                    $Body = @{ Results = "No credential with keyId $KeyId exists on the CIPP-SAM application." }
                    break
                }
                $null = Set-CIPPSAMCredentialRecord -KeyId $KeyId -Label $Label -Headers $Headers
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Marked CIPP-SAM credential keyId $KeyId as known: $Label" -sev Alert
                $Body = @{ Results = @{ message = "Marked the credential as known: $Label"; severity = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Failed to mark CIPP-SAM credential keyId $KeyId as known: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Failed to mark the credential as known: $($ErrorMessage.NormalizedError)" }
            }
        }

        'UnflagCredential' {
            $KeyId = [string]$Request.Body.keyId
            if ($KeyId -notmatch $GuidPattern) {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Body = @{ Results = 'A valid credential keyId is required.' }
                break
            }
            try {
                # Provenance of CIPP-created credentials survives; only the admin label is cleared.
                $Flag = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'SAMCredential' and RowKey eq '$KeyId'"
                if ($Flag.Source) {
                    $null = Add-CIPPAzDataTableEntity @ConfigTable -Entity @{ PartitionKey = 'SAMCredential'; RowKey = $KeyId; Source = [string]$Flag.Source; Actor = [string]$Flag.Actor; CreatedBy = [string]$Flag.CreatedBy; CreatedAt = [string]$Flag.CreatedAt } -Force
                } elseif ($Flag) {
                    Remove-AzDataTableEntity @ConfigTable -Entity $Flag -Force
                }
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Removed the known flag from CIPP-SAM credential keyId $KeyId" -sev Alert
                $Body = @{ Results = @{ message = 'Removed the known flag from the credential.'; severity = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Failed to unflag CIPP-SAM credential keyId $KeyId`: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Failed to remove the known flag: $($ErrorMessage.NormalizedError)" }
            }
        }

        'ClearTokenCache' {
            try {
                $Removed = Clear-CippTokenCache
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "Manual token cache clear: invalidated $Removed cached token entries." -sev Info
                $Body = @{ Results = @{ message = "Cleared $Removed cached token entries. Every worker fetches fresh tokens on its next call."; severity = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Failed to clear the token cache: $($ErrorMessage.NormalizedError)" }
            }
        }

        'RunTokenUpdate' {
            # Inline, the same way the timers page's Run Now invokes a timer command.
            try {
                Start-UpdateTokensTimer -Confirm:$false
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message 'Ran the token update on demand' -sev Info
                $Body = @{ Results = @{ message = 'Token update completed. Check the logbook for anything it changed.'; severity = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message "On-demand token update failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Token update failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        default {
            $StatusCode = [HttpStatusCode]::BadRequest
            $Body = @{ Results = "Unknown action: $Action. Use 'Status', 'RotateSecret', 'RevokeCredential', 'FlagCredential', 'UnflagCredential', 'ClearTokenCache' or 'RunTokenUpdate'." }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = $Body
    }
}
