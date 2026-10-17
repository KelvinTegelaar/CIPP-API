function Invoke-ExecCombinedSetup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    #Make arraylist of Results
    $Results = [System.Collections.ArrayList]::new()
    $StatusCode = [HttpStatusCode]::OK
    try {
        # Certificate-auth toggle for an existing install: enabling keeps the client secret as a rollback
        # and switches SAM tokens to the certificate. Idempotent with a certificate-only First Setup.
        if ($null -ne $Request.Body.certificateAuth) {
            # Ensure credentials are loaded so the secret-usability check below is accurate on a cold
            # runspace (otherwise a legitimate secret-based install could be wrongly refused a disable).
            $null = Get-CIPPAuthentication
            if ($Request.Body.certificateAuth -eq $true) {
                try {
                    # Make sure the certificate exists and is registered on the app before switching to it.
                    $null = Update-CIPPSAMCertificate -ErrorAction Stop
                    $Cert = Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop
                    if (-not $Cert) { throw 'No SAM certificate is available to authenticate with.' }
                    # Only switch over once the certificate has proven it can obtain a token.
                    $Probe = Test-CIPPSAMCertificateAuth
                    if (-not $Probe.Success) {
                        $Results.add("Could not enable certificate authentication: the SAM certificate $($Probe.Thumbprint) could not obtain a token ($($Probe.Error)). The client secret remains in use.")
                    } else {
                        $null = Set-CIPPFeatureFlag -Id 'CertificateAuthentication' -Enabled $true -Force
                        $env:CertificateAuthMode = $true
                        $null = Set-CIPPCredentialVersion
                        Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint ?? 'CombinedSetup') -tenant 'Global' -message "Manual change: CIPP-SAM authentication switched to the certificate (thumbprint $($Cert.Thumbprint)). The client secret is kept as a rollback." -Sev 'Alert'
                        $Results.add('Enabled certificate authentication. CIPP now authenticates with the SAM certificate instead of the client secret. The client secret is kept as a rollback - disable this option to switch back.')
                    }
                } catch {
                    $Results.add("Could not enable certificate authentication: $($_.Exception.Message). The existing authentication method is unchanged.")
                }
            } else {
                # Disabling needs a usable secret to fall back to. A certificate-only install has none,
                # so mint one now while the certificate still authenticates the Graph calls, tracked
                # like every other rotation. Only switch once the new secret can obtain a token.
                $SecretPlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
                $SecretUsable = $env:ApplicationSecret -and $env:ApplicationSecret -notmatch $SecretPlaceholderPattern
                $Minted = $false
                if (-not $SecretUsable) {
                    try {
                        $null = Update-CIPPSAMSecret -DisplayName 'UpdateTokens' -Source 'Manual' -Headers $Request.Headers -APIName ($Request.Params.CIPPEndpoint ?? 'CombinedSetup')
                        $Minted = $true
                        $SecretUsable = $true
                    } catch {
                        $Results.add("Certificate authentication cannot be disabled: this install has no client secret and creating one failed. $($_.Exception.Message)")
                    }
                }
                if ($SecretUsable) {
                    # A fresh secret takes Entra a few minutes to activate; do not switch until it works.
                    $Probe = Test-CIPPSAMSecret -IncludeRefreshGrant
                    for ($Attempt = 0; $Minted -and -not $Probe.ready -and $Probe.reason -eq 'propagating' -and $Attempt -lt 9; $Attempt++) {
                        Start-Sleep -Seconds 5
                        $Probe = Test-CIPPSAMSecret -IncludeRefreshGrant
                    }
                    if ($Probe.ready) {
                        $null = Set-CIPPFeatureFlag -Id 'CertificateAuthentication' -Enabled $false -Force
                        $env:CertificateAuthMode = $null
                        $null = Set-CIPPCredentialVersion
                        $null = Clear-CippTokenCache
                        Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint ?? 'CombinedSetup') -tenant 'Global' -message "Manual change: CIPP-SAM authentication switched to the client secret$(if ($Minted) { ' (a new secret was created for this)' })." -Sev 'Alert'
                        $Results.add($(if ($Minted) { 'Created a new client secret and disabled certificate authentication. CIPP now uses the client secret.' } else { 'Disabled certificate authentication. CIPP will use the client secret again.' }))
                    } elseif ($Probe.reason -eq 'propagating') {
                        $Results.add($(if ($Minted) { 'Created a new client secret, but Microsoft has not finished activating it. Certificate authentication stays on for now - disable it again in a few minutes.' } else { 'The client secret was rotated recently and Microsoft has not finished activating it. Certificate authentication stays on for now - disable it again in a few minutes.' }))
                    } else {
                        $Results.add("Certificate authentication cannot be disabled: the stored client secret does not work ($($Probe.message)). Rotate the secret from the Credentials page first.")
                    }
                }
            }
        }

        if ($request.body.selectedBaselines -and $request.body.baselineOption -eq 'downloadBaselines') {
            #do a single download of the selected baselines.
            foreach ($template in $request.body.selectedBaselines) {
                $object = @{
                    TenantFilter  = 'No tenant'
                    Name          = "Download Single Baseline: $($template.value)"
                    Command       = @{
                        value = 'New-CIPPTemplateRun'
                    }
                    Parameters    = @{
                        TemplateSettings = @{
                            ca                 = $false
                            intuneconfig       = $false
                            intunecompliance   = $false
                            intuneprotection   = $false
                            templateRepo       = @{
                                label       = $Template.label
                                value       = $template.value
                                addedFields = @{
                                    branch = 'main'
                                }
                            }
                            templateRepoBranch = @{
                                label = 'main'
                                value = 'main'
                            }
                            standardsconfig    = $true
                            groupTemplates     = $true
                            policyTemplates    = $true
                            caTemplates        = $true
                        }
                    }
                    ScheduledTime = 0
                }
                $null = Add-CIPPScheduledTask -task $object -hidden $false -DisallowDuplicateName $true -Headers $Request.Headers
                $Results.add("Scheduled download of baseline: $($template.value)")
            }
        }
        if ($Request.body.email -or $Request.body.webhook) {
            #create hashtable from pscustomobject
            $notificationConfig = $request.body | Select-Object email, webhook, onepertenant, logsToInclude, sendtoIntegration, sev | ConvertTo-Json | ConvertFrom-Json -AsHashtable
            $notificationResults = Set-CIPPNotificationConfig @notificationConfig
            $Results.add($notificationResults)
            if ($notificationResults -like 'Failed*') {
                Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint ?? 'CombinedSetup') -tenant 'Global' -message $notificationResults -Sev 'Error'
            } else {
                Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint ?? 'CombinedSetup') -tenant 'Global' -message $notificationResults -Sev 'Info'
            }
        }
        if ($Request.Body.selectedOption -eq 'Manual') {
            $KV = Get-CippKeyVaultName

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                if (!$Secret) {
                    $Secret = [PSCustomObject]@{
                        'PartitionKey'      = 'Secret'
                        'RowKey'            = 'Secret'
                        'TenantId'          = ''
                        'RefreshToken'      = ''
                        'ApplicationId'     = ''
                        'ApplicationSecret' = ''
                    }
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                }

                if ($Request.Body.tenantId) { $Secret.TenantId = $Request.Body.tenantid }
                if ($Request.Body.applicationId) { $Secret.ApplicationId = $Request.Body.applicationId }
                if ($Request.Body.ApplicationSecret) { $Secret.ApplicationSecret = $Request.Body.ApplicationSecret }
                if ($Request.Body.RefreshToken) { $Secret.RefreshToken = $Request.Body.RefreshToken }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                $Results.add('Manual credentials have been set in the DevSecrets table.')
            } else {
                if ($Request.Body.tenantId) {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $Request.Body.tenantId -AsPlainText -Force)
                    $Results.add('Set tenant ID in Key Vault.')
                }
                if ($Request.Body.applicationId) {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationId -AsPlainText -Force)
                    $Results.add('Set application ID in Key Vault.')
                }
                if ($Request.Body.applicationSecret) {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationSecret -AsPlainText -Force)
                    $Results.add('Set application secret in Key Vault.')
                }
                if ($Request.Body.RefreshToken) {
                    Set-CippKeyVaultSecret -VaultName $kv -Name 'refreshtoken' -SecretValue (ConvertTo-SecureString -String $Request.Body.RefreshToken -AsPlainText -Force)
                    $Results.add('Set refresh token in Key Vault.')
                }
            }

            # A pasted secret has no known keyId, so stop attributing any app secret to this instance.
            if ($Request.Body.applicationSecret) {
                $ConfigTable = Get-CIPPTable -tablename 'Config'
                $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
                $null = Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
                    PartitionKey  = 'AppCache'
                    RowKey        = 'AppCache'
                    ApplicationId = [string]($Request.Body.applicationId ?? $AppCache.ApplicationId)
                    SecretKeyId   = ''
                } -Force
                $null = Set-CIPPCredentialVersion
                Write-LogMessage -headers $Request.Headers -API ($Request.Params.CIPPEndpoint ?? 'CombinedSetup') -tenant 'Global' -message 'CIPP-SAM client secret replaced manually; its keyId is unknown to CIPP.' -Sev 'Alert'
            }
            $Results.add('Manual credentials setup has been completed.')
        }

        $Results.add('Setup is now complete. You may navigate away from this page and start using CIPP.')
        #one more force of reauth so env vars update.
        $auth = Get-CIPPAuthentication
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $($_.Exception.message)"; severity = 'failed' }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
