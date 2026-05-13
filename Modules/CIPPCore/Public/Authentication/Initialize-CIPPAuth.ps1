function Initialize-CIPPAuth {
    <#
    .SYNOPSIS
    Bootstraps authentication state for CIPP.

    .DESCRIPTION
    Loads SAM credentials from Key Vault (or DevSecrets table),
    auto-patches redirect URIs on the SAM and SSO app registrations,
    and configures EasyAuth if SSO credentials are provisioned but
    EasyAuth is not yet enabled.
    #>
    [CmdletBinding()]
    param()

    $AuthState = @{
        IsConfigured      = $false
        HasKeyVault       = $false
        HasSAMCredentials = $false
        NeedsSetup        = $true
    }

    # 1. Determine Key Vault name
    $KVName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]

    # 2. Try loading SAM credentials
    if ($KVName -or $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $AuthState.HasKeyVault = [bool]$KVName
        try {
            $Auth = Get-CIPPAuthentication
            if ($Auth -and $env:ApplicationID -and $env:TenantID) {
                $AuthState.HasSAMCredentials = $true
                $AuthState.NeedsSetup = $false
                $AuthState.IsConfigured = $true
                Write-Information "[Auth-Init] SAM credentials loaded (AppID: $($env:ApplicationID))"
            }
        } catch {
            Write-Information "[Auth-Init] Could not load SAM credentials: $_"
        }
    }

    # 3. Auto-patch redirect URIs if we have credentials
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

    # 4. If EasyAuth is not configured, check for SSO credentials and set it up
    $EasyAuthEnabled = [Craft.Services.AppLifecycleBridge]::IsEasyAuthConfigured()
    if (-not $EasyAuthEnabled -and $AuthState.HasSAMCredentials) {
        # If the central migration app ID is set, configure EasyAuth with implicit auth
        # (no client secret). This lets the user log in via the shared app while the
        # ForcedSsoMigrationDialog guides them through creating their own CIPP-SSO app.
        # Once they complete migration, step 5 detects the clientId change and cleans up.
        if ($env:CIPP_SSO_MIGRATION_APPID) {
            Write-Information "[Auth-Init] CIPP_SSO_MIGRATION_APPID is set ($($env:CIPP_SSO_MIGRATION_APPID)) — configuring implicit auth EasyAuth"
            try {
                $Configured = Set-CIPPSSOEasyAuth -AppId $env:CIPP_SSO_MIGRATION_APPID -MultiTenant $false -TenantId $env:TenantID -UseKvReferences -ImplicitAuth
                if ($Configured) {
                    Write-Information '[Auth-Init] Implicit auth EasyAuth configured — requesting restart'
                    [Craft.Services.AppLifecycleBridge]::RequestRestart('Implicit auth EasyAuth configured with central migration app during warmup')
                }
            } catch {
                Write-Information "[Auth-Init] Implicit auth EasyAuth setup failed (non-fatal): $_"
            }
            return $AuthState
        }

        Write-Information '[Auth-Init] EasyAuth not configured — checking for SSO credentials...'
        try {
            $SSOAppId = $null
            $SSOMultiTenant = $false

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
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
                    [Craft.Services.AppLifecycleBridge]::RequestRestart('EasyAuth configured from SSO credentials during warmup')
                }
            } else {
                Write-Information '[Auth-Init] No SSO credentials found — enabling setup wizard'
                [Craft.Services.AppLifecycleBridge]::RequestSetupMode('No SSO credentials found — setup wizard needed for initial EasyAuth configuration')
            }
        } catch {
            Write-Information "[Auth-Init] SSO EasyAuth setup failed (non-fatal): $_"
        }
    }

    # 5. Post-migration cleanup: if CIPP_SSO_MIGRATION_APPID is still set but EasyAuth
    #    is now configured, check whether the EasyAuth clientId still matches the migration
    #    app. If it differs, the customer's own CIPP-SSO app is active and we can remove
    #    the migration trigger env var.
    if ($EasyAuthEnabled -and $env:CIPP_SSO_MIGRATION_APPID) {
        Write-Information '[Auth-Init] EasyAuth is active but CIPP_SSO_MIGRATION_APPID still set — checking if migration is complete...'
        try {
            $AuthConfigJson = $env:WEBSITE_AUTH_V2_CONFIG_JSON
            if ($AuthConfigJson) {
                $AuthConfig = $AuthConfigJson | ConvertFrom-Json -ErrorAction Stop
                $ConfiguredAppId = $AuthConfig.identityProviders.azureActiveDirectory.registration.clientId

                if ($ConfiguredAppId -eq $env:CIPP_SSO_MIGRATION_APPID) {
                    # EasyAuth is still using the central migration app — migration not done yet
                    Write-Information '[Auth-Init] EasyAuth clientId matches migration app — migration still pending'
                } elseif ($ConfiguredAppId) {
                    # EasyAuth clientId differs from the migration app — customer's own app is active
                    Write-Information "[Auth-Init] EasyAuth clientId ($ConfiguredAppId) differs from migration app — migration complete, cleaning up"
                    $Removed = Remove-CIPPMigrationAppSetting -SettingName 'CIPP_SSO_MIGRATION_APPID'
                    if ($Removed) {
                        [Craft.Services.AppLifecycleBridge]::RequestRestart('SSO migration env var cleaned up during warmup')
                    }
                } else {
                    Write-Information '[Auth-Init] No clientId found in EasyAuth config — skipping cleanup'
                }
            }
        } catch {
            Write-Information "[Auth-Init] Migration cleanup check failed (non-fatal): $_"
        }
    }

    return $AuthState
}
