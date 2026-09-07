function Invoke-ExecCreateSAMApp {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $KV = Get-CippKeyVaultName

    try {
        $Token = $Request.body
        if ($Token) {
            # A certificate-only setup provisions no client secret. Determined up front so every app
            # management policy call in this flow leaves the password-addition block in force.
            $CertificateOnly = $Request.body.certificateOnly -eq $true
            $URL = $Request.headers.origin ?? $Request.headers.referer?.TrimEnd('/')
            $RedirectUri = "$URL/authredirect"
            $AuthCallbackUri = "$URL/.auth/callback"
            $TenantId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/organization' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method GET -ContentType 'application/json').value.id
            #Find Existing app registration
            $AppId = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq 'CIPP-SAM'" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method GET -ContentType 'application/json').value | Select-Object -Last 1
            #Check if the appId has the redirect URI, if not, add it.
            if ($AppId) {
                Write-Host "Found existing app: $($AppId.id). Reusing."
                $state = 'updated'
                #remove the entire web object from the app registration
                $SamManifestFile = Get-Item (Join-Path $env:CIPPRootPath 'Config\SAMManifest.json')
                $app = Get-Content $SamManifestFile.FullName | ConvertFrom-Json
                $app.web.redirectUris = @($RedirectUri, $AuthCallbackUri)
                $app = ConvertTo-Json -Depth 15 -Compress -InputObject $app
                Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppId.id)" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method PATCH -Body $app -ContentType 'application/json'
            } else {
                $state = 'created'
                $SamManifestFile = Get-Item (Join-Path $env:CIPPRootPath 'Config\SAMManifest.json')
                $app = Get-Content $SamManifestFile.FullName | ConvertFrom-Json
                $app.web.redirectUris = @($RedirectUri, $AuthCallbackUri)
                $app = $app | ConvertTo-Json -Depth 15
                $AppId = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/applications' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body $app -ContentType 'application/json')
                $attempt = 0
                do {
                    try {
                        try {
                            $SPNDefender = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"fc780465-2017-40d4-a0c5-307022471b92`" }" -ContentType 'application/json')
                        } catch {
                            Write-Information "didn't deploy spn for defender, probably already there."
                        }
                        try {
                            $SPNTeams = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"48ac35b8-9aa8-4d74-927d-1f4a14a0b239`" }" -ContentType 'application/json')
                        } catch {
                            Write-Information "didn't deploy spn for Teams, probably already there."
                        }
                        try {
                            $SPNO365Manage = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"c5393580-f805-4401-95e8-94b7a6ef2fc2`" }" -ContentType 'application/json')
                        } catch {
                            Write-Information "didn't deploy spn for O365 Management, probably already there."
                        }
                        try {
                            $SPNPartnerCenter = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd`" }" -ContentType 'application/json')
                        } catch {
                            Write-Information "didn't deploy spn for PartnerCenter, probably already there."
                        }
                        $SPN = (Invoke-RestMethod 'https://graph.microsoft.com/v1.0/servicePrincipals' -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body "{ `"appId`": `"$($AppId.appId)`" }" -ContentType 'application/json')
                        Start-Sleep 2
                        $attempt ++
                    } catch {
                        $attempt ++
                    }
                } until ($attempt -gt 3)
            }

            try {

                $AppPolicyStatus = Update-AppManagementPolicy -Headers @{ authorization = "Bearer $($Token.access_token)" } -ApplicationId $appId.appId -CertificateOnly $CertificateOnly
                Write-Information $AppPolicyStatus.PolicyAction
            } catch {
                Write-Warning "Error updating app management policy $($_.Exception.Message)."
                Write-Information ($_.InvocationInfo.PositionMessage)
            }

            # A certificate-only setup provisions no client secret - the SAM certificate is the sole
            # credential. Register it now (before the token step, which will authenticate with it) and
            # turn on the feature flag so the reload below resolves certificate mode.
            if ($CertificateOnly) {
                try {
                    # Enable certificate mode BEFORE provisioning so the app management policy exemption
                    # leaves the password-addition block in force (no client secret is ever added).
                    $null = Set-CIPPFeatureFlag -Id 'CertificateAuthentication' -Enabled $true -Force
                    $env:CertificateAuthMode = $true
                    $CertResult = Update-CIPPSAMCertificate -ApplicationId $AppId.appId -Headers @{ authorization = "Bearer $($Token.access_token)" } -ErrorAction Stop
                    Write-Information "Registered SAM certificate for certificate-only setup. Thumbprint: $($CertResult.Thumbprint), storage mode: $($CertResult.StorageMode)"
                } catch {
                    throw "Certificate-only setup was selected but the SAM certificate could not be registered on the application. Setup cannot continue without a credential. $($_.Exception.Message)"
                }
                $AppPassword = $null
            } else {
                $AppPassword = (Invoke-RestMethod "https://graph.microsoft.com/v1.0/applications/$($AppId.id)/addPassword" -Headers @{ authorization = "Bearer $($Token.access_token)" } -Method POST -Body '{"passwordCredential":{"displayName":"CIPPInstall"}}' -ContentType 'application/json').secretText
            }

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                if (!$Secret) { $Secret = New-Object -TypeName PSObject }
                $Secret | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value 'Secret' -Force
                $Secret | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value 'Secret' -Force
                $Secret | Add-Member -MemberType NoteProperty -Name 'tenantid' -Value $TenantId -Force
                $Secret | Add-Member -MemberType NoteProperty -Name 'applicationid' -Value $AppId.appId -Force
                # Blank the stored secret in certificate-only mode so CIPP falls through to the certificate
                $Secret | Add-Member -MemberType NoteProperty -Name 'applicationsecret' -Value ($AppPassword ?? '') -Force
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            } else {
                Set-CippKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $TenantId -AsPlainText -Force)
                Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Appid.appId -AsPlainText -Force)
                # Certificate-only setups create no secret; leave the placeholder in place so it reads
                # back as unusable and CIPP authenticates with the certificate instead.
                if ($AppPassword) {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $AppPassword -AsPlainText -Force)
                }
            }
            # Populate this process straight from the values we just created. The wizard
            # moves to the next step immediately and every reader treats $env:ApplicationID
            # as the "setup complete" signal, so nothing downstream should have to wait on
            # the store catching up.
            $env:ApplicationID = $AppId.appId
            $env:TenantID = $TenantId
            $env:ApplicationSecret = $AppPassword

            # Then confirm the store actually hands back what we just wrote. Fresh
            # deployments seed the vault with the deployment template's placeholder values
            # rather than leaving the secrets absent, so a write that is not visible yet
            # reads back as 'LongApplicationId' instead of 404-ing - which is how a
            # correctly configured instance ends up looking like setup never ran. Poll
            # before reporting success, and before the Get-CIPPAuthentication reload below
            # has a chance to put those placeholders back over the new credentials.
            $ReadAttempts = 3
            $ReadDelay = 2
            $SecretsReadable = $false
            for ($ReadAttempt = 1; $ReadAttempt -le $ReadAttempts; $ReadAttempt++) {
                try {
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                        $StoredAppId = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'").applicationid
                    } else {
                        $StoredAppId = Get-CippKeyVaultSecret -AsPlainText -VaultName $kv -Name 'ApplicationID'
                    }
                    if ($StoredAppId -eq $AppId.appId) {
                        $SecretsReadable = $true
                        break
                    }
                    Write-Information "Attempt $ReadAttempt of $ReadAttempts - stored application id is '$StoredAppId', expected '$($AppId.appId)'. Waiting for the write to become visible."
                } catch {
                    Write-Information "Attempt $ReadAttempt of $ReadAttempts - could not read the application id back: $($_.Exception.Message)"
                }
                if ($ReadAttempt -lt $ReadAttempts) {
                    Start-Sleep -Seconds $ReadDelay
                    $ReadDelay *= 2
                }
            }
            if (-not $SecretsReadable) {
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Created the application registration but could not read the application id back from storage after $ReadAttempts attempts. This instance holds the new credentials, but other instances may still serve the previous values until the write propagates." -Sev 'Warning'
            }

            $ConfigTable = Get-CippTable -tablename 'Config'
            #update the ConfigTable with the latest appId, for caching compare.
            $NewConfig = @{
                PartitionKey  = 'AppCache'
                RowKey        = 'AppCache'
                ApplicationId = $AppId.appId
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $NewConfig -Force | Out-Null

            # Reload credentials into env vars
            $null = Get-CIPPAuthentication

            # The reload above reads the store back unconditionally, so if it was still
            # serving the old values it just overwrote the credentials we created. The
            # values from this request are the authoritative ones - put them back.
            if ($env:ApplicationID -ne $AppId.appId) {
                Write-Information "Credential reload returned application id '$($env:ApplicationID)' - restoring the one created by this request."
                $env:ApplicationID = $AppId.appId
                $env:TenantID = $TenantId
                $env:ApplicationSecret = $AppPassword
            }

            # Create the SAM certificate alongside the secret so certificate auth is available
            # immediately. Uses the wizard's delegated token because the app secret was created
            # seconds ago and may not have propagated yet. Non-fatal: the weekly token update
            # timer creates the certificate if this fails.
            try {
                $CertResult = Update-CIPPSAMCertificate -ApplicationId $AppId.appId -Headers @{ authorization = "Bearer $($Token.access_token)" }
                if ($CertResult.Renewed) {
                    Write-Information "SAM certificate created. Thumbprint: $($CertResult.Thumbprint), expires: $($CertResult.NotAfter), storage mode: $($CertResult.StorageMode)"
                }
            } catch {
                Write-Warning "Failed to create SAM certificate during setup, the weekly token update will create it: $($_.Exception.Message)"
            }

            $CredentialNote = if ($CertificateOnly) { ' This is a certificate-only setup - no client secret was created, and CIPP will authenticate with the SAM certificate.' } else { '' }
            $Results = @{'message' = "Successfully $state the application registration. The application ID is $($AppId.appid).$CredentialNote You may continue to the next step."; severity = 'success' }
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Successfully $state CIPP-SAM application registration AppId=$($AppId.appId) (certificate-only=$CertificateOnly)" -Sev 'Info'
        }

    } catch {
        # ErrorDetails holds the HTTP response body (Graph / Key Vault error JSON);
        # the exception message alone is just the status line, which made failures
        # like a soft-deleted Key Vault secret (409) undiagnosable from the UI
        $ErrorDetail = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to create or update CIPP-SAM application registration: $ErrorDetail" -Sev 'Error'
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $ErrorDetail"; severity = 'failed' }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
