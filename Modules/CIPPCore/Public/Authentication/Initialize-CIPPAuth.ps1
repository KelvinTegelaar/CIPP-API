function Initialize-CIPPAuth {
    <#
    .SYNOPSIS
    Bootstraps authentication state for CIPP.

    .DESCRIPTION
    Loads SAM credentials from Key Vault (or DevSecrets table),
    auto-patches redirect URIs on the SAM and SSO app registrations,
    and configures EasyAuth if SSO credentials are provisioned but
    EasyAuth is not yet enabled. On a fresh deployment with nothing
    configured, requests Craft's setup wizard mode.
    #>
    [CmdletBinding()]
    param()

    $AuthState = @{
        IsConfigured      = $false
        HasKeyVault       = $false
        HasSAMCredentials = $false
        NeedsSetup        = $true
    }

    # -- Entry logging --
    $EasyAuthEnabled = [Craft.Services.AppLifecycleBridge]::IsEasyAuthConfigured()
    $IsDevStorage = ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') -or ($env:NonLocalHostAzurite -eq 'true')
    $KVName = Get-CippKeyVaultName

    Write-Information "[Auth-Init] Starting — EasyAuth=$EasyAuthEnabled, DevStorage=$IsDevStorage, KVName='$KVName', DeploymentId='$env:WEBSITE_DEPLOYMENT_ID'"

    # 1. Try loading SAM credentials
    if ($KVName -or $IsDevStorage) {
        $AuthState.HasKeyVault = [bool]$KVName
        Write-Information "[Auth-Init] Credential source available (KV=$($AuthState.HasKeyVault), DevStorage=$IsDevStorage) — attempting SAM load"
        try {
            $Auth = Get-CIPPAuthentication
            if ($Auth -and $env:ApplicationID -and $env:TenantID) {
                $AuthState.HasSAMCredentials = $true
                $AuthState.NeedsSetup = $false
                $AuthState.IsConfigured = $true
                Write-Information "[Auth-Init] SAM credentials loaded (AppID: $($env:ApplicationID), TenantID: $($env:TenantID))"
            } else {
                Write-Information '[Auth-Init] SAM credential load returned but env vars not populated — credentials not available yet (expected on fresh deployment)'
            }
        } catch {
            $ErrorMessage = "$_"
            # Distinguish "not found" from real access errors
            if ($ErrorMessage -match 'SecretNotFound|not found|does not exist|Development variables not set') {
                Write-Information "[Auth-Init] SAM credentials not found in storage — expected on fresh deployment"
            } else {
                Write-Information "[Auth-Init] ERROR accessing credential storage (possible permission/network issue): $ErrorMessage"
            }
        }
    } else {
        Write-Information '[Auth-Init] No credential source available — WEBSITE_DEPLOYMENT_ID is not set and not using dev storage. Cannot load SAM credentials.'
    }

    # 2. Auto-patch redirect URIs if we have credentials
    if ($AuthState.HasSAMCredentials) {
        try {
            Update-CIPPSAMRedirectUri
        } catch {
            Write-Information "[Auth-Init] SAM redirect URI patch failed (non-fatal): $_"
        }

        try {
            Update-CIPPSSORedirectUri
        } catch {
            Write-Information "[Auth-Init] SSO redirect URI patch failed (non-fatal): $_"
        }
    }

    # 3. Handle EasyAuth configuration based on current state
    if ($EasyAuthEnabled) {
        Write-Information '[Auth-Init] EasyAuth is already configured'

        # 3a. If CIPP_SSO_MIGRATION_APPID is set, check if migration is complete
        if ($env:CIPP_SSO_MIGRATION_APPID) {
            Write-Information '[Auth-Init] EasyAuth is active but CIPP_SSO_MIGRATION_APPID still set — checking if migration is complete...'
            try {
                $AuthConfigJson = $env:WEBSITE_AUTH_V2_CONFIG_JSON
                if ($AuthConfigJson) {
                    $AuthConfig = $AuthConfigJson | ConvertFrom-Json -ErrorAction Stop
                    $ConfiguredAppId = $AuthConfig.identityProviders.azureActiveDirectory.registration.clientId

                    if ($ConfiguredAppId -eq $env:CIPP_SSO_MIGRATION_APPID) {
                        Write-Information '[Auth-Init] EasyAuth clientId matches migration app — migration still pending'
                    } elseif ($ConfiguredAppId) {
                        Write-Information "[Auth-Init] EasyAuth clientId ($ConfiguredAppId) differs from migration app — migration complete, cleaning up"
                        $Removed = Remove-CIPPMigrationAppSetting -SettingName 'CIPP_SSO_MIGRATION_APPID'
                        if ($Removed) {
                            Request-CIPPRestart -Reason 'SSO migration env var cleaned up during warmup'
                        }
                    } else {
                        Write-Information '[Auth-Init] No clientId found in EasyAuth config — skipping cleanup'
                    }
                }
            } catch {
                Write-Information "[Auth-Init] Migration cleanup check failed (non-fatal): $_"
            }
        }

        # 3b. Reconcile EasyAuth issuer with SSOMultiTenant setting
        if ($AuthState.HasSAMCredentials -and -not $env:CIPP_SSO_MIGRATION_APPID) {
            try {
                $AuthConfigJson = $env:WEBSITE_AUTH_V2_CONFIG_JSON
                if ($AuthConfigJson) {
                    $AuthConfig = $AuthConfigJson | ConvertFrom-Json -ErrorAction Stop
                    $CurrentIssuer = $AuthConfig.identityProviders.azureActiveDirectory.registration.openIdIssuer
                    $ConfiguredAppId = $AuthConfig.identityProviders.azureActiveDirectory.registration.clientId

                    if ($CurrentIssuer -and $ConfiguredAppId) {
                        $SSOMultiTenant = $false
                        if ($IsDevStorage) {
                            try {
                                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                                $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                                $SSOMultiTenant = $Secret.SSOMultiTenant -eq 'True'
                            } catch { }
                        } elseif ($KVName) {
                            try {
                                $MtVal = Get-CippKeyVaultSecret -VaultName $KVName -Name 'SSOMultiTenant' -AsPlainText -ErrorAction Stop
                                $SSOMultiTenant = $MtVal -eq 'True'
                            } catch { }
                        }

                        $ExpectedIssuer = if ($SSOMultiTenant) {
                            'https://login.microsoftonline.com/common/v2.0'
                        } else {
                            "https://login.microsoftonline.com/$($env:TenantID)/v2.0"
                        }

                        if ($CurrentIssuer -ne $ExpectedIssuer) {
                            Write-Information "[Auth-Init] EasyAuth issuer mismatch: current=$CurrentIssuer expected=$ExpectedIssuer — updating"
                            $Configured = Set-CIPPSSOEasyAuth -AppId $ConfiguredAppId -MultiTenant $SSOMultiTenant -TenantId $env:TenantID
                            if ($Configured) {
                                Write-Information '[Auth-Init] EasyAuth issuer updated — requesting container restart'
                                Request-CIPPRestart -Reason 'EasyAuth issuer updated to match SSOMultiTenant setting during warmup'
                            }
                        } else {
                            Write-Information "[Auth-Init] EasyAuth issuer matches SSOMultiTenant setting ($SSOMultiTenant) — no update needed"
                        }
                    }
                }
            } catch {
                Write-Information "[Auth-Init] EasyAuth issuer reconciliation failed (non-fatal): $_"
            }
        }

        # 3c. Reconcile EasyAuth policy (UnauthenticatedClientAction, ExcludedPaths) with appsettings configuration
        if ($AuthState.HasSAMCredentials -and -not $env:CIPP_SSO_MIGRATION_APPID) {
            try {
                $PolicyReconciled = [Craft.Services.AppLifecycleBridge]::ReconcileAuthPolicy('CIPP warmup')
                if ($PolicyReconciled) {
                    Write-Information '[Auth-Init] EasyAuth policy reconciled from Craft appsettings (drift detected and corrected)'
                } else {
                    Write-Information '[Auth-Init] EasyAuth policy matches appsettings — no update needed'
                }
            } catch {
                Write-Information "[Auth-Init] EasyAuth policy reconcile failed (non-fatal): $_"
            }
        }

        # 3d. Reconcile API clients — ensure the EasyAuth config matches what the
        # "Save to Azure" action (Set-CippApiAuth) would produce for the currently
        # enabled API clients. That means BOTH lists must be checked, not just apps:
        #   allowedApplications = SSO app + every enabled client
        #   allowedAudiences    = api://<id> for each of the above, plus the MCP host
        #                         URIs and bare client IDs for MCP-enabled clients
        # Config drifts when a client is enabled but "Save to Azure" was never run (or a
        # prior save partially applied — e.g. apps set but audiences missing), which
        # silently breaks API authentication for that client.
        if ($AuthState.HasSAMCredentials -and -not $env:CIPP_SSO_MIGRATION_APPID -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
            try {
                $ApiClientsTable = Get-CippTable -tablename 'ApiClients'
                $EnabledClients = @(Get-CIPPAzDataTableEntity @ApiClientsTable -Filter 'Enabled eq true' | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) })

                if ($EnabledClients.Count -gt 0) {
                    $EnabledClientIds = @($EnabledClients.RowKey)
                    # MCPAllowed can round-trip as a bool or string; compare on string form (matches SaveToAzure)
                    $McpClientIds = @($EnabledClients | Where-Object { "$($_.MCPAllowed)" -eq 'True' } | ForEach-Object { $_.RowKey })

                    $ApiAuthConfig = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction Stop
                    $AADConfig = $ApiAuthConfig.identityProviders.azureActiveDirectory

                    # Desired state — keep in sync with Set-CippApiAuth's CIPPNG branch.
                    $DesiredApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    if ($AADConfig.registration.clientId) { [void]$DesiredApps.Add($AADConfig.registration.clientId) }
                    foreach ($Id in $EnabledClientIds) { if (-not [string]::IsNullOrEmpty($Id)) { [void]$DesiredApps.Add($Id) } }

                    $DesiredAudiences = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($Id in $DesiredApps) { [void]$DesiredAudiences.Add("api://$Id") }
                    if ($McpClientIds.Count -gt 0 -and $env:WEBSITE_HOSTNAME) {
                        [void]$DesiredAudiences.Add("https://$($env:WEBSITE_HOSTNAME)")
                        [void]$DesiredAudiences.Add("https://$($env:WEBSITE_HOSTNAME)/api/ExecMcp")
                        foreach ($McpId in $McpClientIds) { if (-not [string]::IsNullOrEmpty($McpId)) { [void]$DesiredAudiences.Add($McpId) } }
                    }

                    # Current state from the platform-injected config
                    $CurrentApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($App in @($AADConfig.validation.defaultAuthorizationPolicy.allowedApplications)) { if ($App) { [void]$CurrentApps.Add($App) } }
                    $CurrentAudiences = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($Aud in @($AADConfig.validation.allowedAudiences)) { if ($Aud) { [void]$CurrentAudiences.Add($Aud) } }

                    # Drift when anything the endpoint would set is missing from the live config
                    $AppsOk = $DesiredApps.IsSubsetOf($CurrentApps)
                    $AudiencesOk = $DesiredAudiences.IsSubsetOf($CurrentAudiences)

                    if (-not $AppsOk -or -not $AudiencesOk) {
                        $MissingApps = @($DesiredApps | Where-Object { -not $CurrentApps.Contains($_) })
                        $MissingAudiences = @($DesiredAudiences | Where-Object { -not $CurrentAudiences.Contains($_) })
                        Write-Information "[Auth-Init] API client drift detected — missing apps: [$($MissingApps -join ', ')]; missing audiences: [$($MissingAudiences -join ', ')] — reconciling EasyAuth"
                        Set-CippApiAuth -TenantId $env:TenantID -ClientIds $EnabledClientIds -McpClientIds $McpClientIds
                        Write-Information '[Auth-Init] EasyAuth allowedApplications + allowedAudiences reconciled with enabled API clients'
                    } else {
                        Write-Information "[Auth-Init] EasyAuth already matches $($EnabledClients.Count) enabled API client(s) — no update needed"
                    }
                }
            } catch {
                Write-Information "[Auth-Init] API client reconcile failed (non-fatal): $_"
            }
        }
    } elseif ($AuthState.HasSAMCredentials) {
        # EasyAuth NOT configured but we DO have SAM credentials — try to auto-configure
        Write-Information '[Auth-Init] EasyAuth not configured but SAM credentials available — attempting auto-configuration'

        if ($env:CIPP_SSO_MIGRATION_APPID) {
            Write-Information "[Auth-Init] CIPP_SSO_MIGRATION_APPID is set ($($env:CIPP_SSO_MIGRATION_APPID)) — configuring implicit auth EasyAuth"
            try {
                $Configured = Set-CIPPSSOEasyAuth -AppId $env:CIPP_SSO_MIGRATION_APPID -MultiTenant $false -TenantId $env:TenantID -UseKvReferences -ImplicitAuth
                if ($Configured) {
                    Write-Information '[Auth-Init] Implicit auth EasyAuth configured — requesting restart'
                    Request-CIPPRestart -Reason 'Implicit auth EasyAuth configured with central migration app during warmup'
                }
            } catch {
                Write-Information "[Auth-Init] Implicit auth EasyAuth setup failed (non-fatal): $_"
            }
            return $AuthState
        }

        # Try to find SSO credentials and configure EasyAuth automatically
        try {
            $SSOAppId = $null
            $SSOMultiTenant = $false

            if ($IsDevStorage) {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                $SSOAppId = $Secret.SSOAppId
                $SSOMultiTenant = $Secret.SSOMultiTenant -eq 'True'
            } elseif ($KVName) {
                try { $SSOAppId = Get-CippKeyVaultSecret -VaultName $KVName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { }
                try {
                    $mtVal = Get-CippKeyVaultSecret -VaultName $KVName -Name 'SSOMultiTenant' -AsPlainText -ErrorAction Stop
                    $SSOMultiTenant = $mtVal -eq 'True'
                } catch { }
            }

            if ($SSOAppId) {
                Write-Information "[Auth-Init] Found SSO AppId ($SSOAppId) — configuring EasyAuth via ARM"
                $Configured = Set-CIPPSSOEasyAuth -AppId $SSOAppId -MultiTenant $SSOMultiTenant -TenantId $env:TenantID -UseKvReferences
                if ($Configured) {
                    Write-Information '[Auth-Init] EasyAuth configured — requesting container restart'
                    Request-CIPPRestart -Reason 'EasyAuth configured from SSO credentials during warmup'
                }
            } else {
                Write-Information '[Auth-Init] SAM credentials loaded but no SSO AppId found — enabling setup wizard'
                [Craft.Services.AppLifecycleBridge]::RequestSetupMode('SAM credentials available but no SSO app configured — setup wizard needed')
            }
        } catch {
            Write-Information "[Auth-Init] SSO EasyAuth setup failed (non-fatal): $_"
            [Craft.Services.AppLifecycleBridge]::RequestSetupMode('SSO setup failed — setup wizard needed for manual configuration')
        }
    } else {
        # No EasyAuth AND no SAM credentials — this is a fresh/unconfigured deployment
        Write-Information '[Auth-Init] Fresh deployment detected — no EasyAuth configured and no SAM credentials available'
        Write-Information '[Auth-Init] Requesting setup wizard mode for initial configuration'
        [Craft.Services.AppLifecycleBridge]::RequestSetupMode('Fresh deployment — no credentials or EasyAuth configured')
        $AuthState.NeedsSetup = $true
    }

    # -- Exit logging --
    Write-Information "[Auth-Init] Complete — IsConfigured=$($AuthState.IsConfigured), HasSAM=$($AuthState.HasSAMCredentials), NeedsSetup=$($AuthState.NeedsSetup), EasyAuth=$EasyAuthEnabled"

    return $AuthState
}
