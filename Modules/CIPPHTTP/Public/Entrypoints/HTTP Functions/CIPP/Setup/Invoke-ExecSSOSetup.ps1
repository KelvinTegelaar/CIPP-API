function Invoke-ExecSSOSetup {
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
    $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Status'
    $MigrationTable = Get-CIPPTable -tablename 'SSOMigration'

    switch ($Action) {
        'Status' {
            # Read live EasyAuth config from the platform-injected env var when available
            if ($env:CIPPNG) {
                try {
                    $EasyAuthEnabled = $env:WEBSITE_AUTH_ENABLED -eq 'True'
                    $ConfigJson = $env:WEBSITE_AUTH_V2_CONFIG_JSON
                    if ($EasyAuthEnabled -and $ConfigJson) {
                        $Config = $ConfigJson | ConvertFrom-Json -ErrorAction Stop
                        $AAD = $Config.identityProviders.azureActiveDirectory
                        $Issuer = $AAD.registration.openIdIssuer ?? ''
                        $ClientId = $AAD.registration.clientId ?? ''
                        $IsMultiTenant = $Issuer -match '/common/'
                        $IssuerTenantId = if (-not $IsMultiTenant -and $Issuer -match 'microsoftonline\.com/([^/]+)/') { $Matches[1] } else { $null }
                        $AllowedAudiences = @($AAD.validation.allowedAudiences)
                        $AllowedApps = @($AAD.validation.defaultAuthorizationPolicy.allowedApplications)
                        $ExcludedPaths = @($Config.globalValidation.excludedPaths)

                        $Body = @{
                            Results = @{
                                configured     = $true
                                status         = 'complete'
                                appId          = $ClientId
                                multiTenant    = $IsMultiTenant
                                tenantId       = $IssuerTenantId
                                issuer         = $Issuer
                                audiences      = $AllowedAudiences
                                allowedApps    = $AllowedApps
                                excludedPaths  = $ExcludedPaths
                                easyAuthActive = $true
                            }
                        }
                    } else {
                        $Body = @{ Results = @{ configured = $false; status = 'none'; easyAuthActive = $false } }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -message "Failed to parse EasyAuth config: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    $Body = @{ Results = @{ configured = $false; status = 'error'; error = $ErrorMessage.NormalizedError } }
                }
            } else {
                # Otherwise read from migration table
                try {
                    $Migration = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                    if ($Migration) {
                        $Body = @{
                            Results = @{
                                configured  = $true
                                status      = $Migration.Status
                                appId       = $Migration.AppId
                                multiTenant = [bool]($Migration.MultiTenant -eq 'true')
                                createdAt   = $Migration.CreatedAt
                                lastChecked = $Migration.LastChecked
                                lastError   = $Migration.LastError
                            }
                        }
                    } else {
                        $Body = @{ Results = @{ configured = $false; status = 'none' } }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -message "Failed to get SSO status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    $Body = @{ Results = @{ configured = $false; status = 'error'; error = $ErrorMessage.NormalizedError } }
                }
            }
        }

        'Create' {
            $MultiTenant = [bool]($Request.Body.multiTenant)
            $TargetUrl = $Request.Body.targetUrl

            # Determine redirect URI — prefer explicit targetUrl, fall back to current host
            if (-not $TargetUrl) {
                $TargetUrl = $Request.Headers.origin ?? $Request.Headers.referer?.TrimEnd('/')
            }
            if (-not $TargetUrl) {
                $TargetUrl = "https://$($env:WEBSITE_HOSTNAME)"
            }

            try {
                # Check if already provisioned
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                if ($Existing -and $Existing.Status -eq 'complete') {
                    $Body = @{
                        Results = @{
                            message  = 'SSO migration already completed.'
                            appId    = $Existing.AppId
                            severity = 'info'
                        }
                    }
                    break
                }

                # If we have an existing record that isn't complete, pick up from where we left off
                $AppId = $Existing.AppId
                $AppSecret = $null

                # Step 1: Create/update the app registration (idempotent)
                # Pass stored AppId so we look up by clientId rather than name
                $SSOAppParams = @{
                    RedirectUri = $TargetUrl
                    MultiTenant = $MultiTenant
                }
                if ($AppId) { $SSOAppParams.ExistingAppId = $AppId }

                $SSOApp = New-CIPPSSOApp @SSOAppParams
                $AppId = $SSOApp.AppId
                $AppSecret = $SSOApp.ClientSecret
                Write-LogMessage -API $APIName -headers $Headers -message "CIPP-SSO app $($SSOApp.State): $AppId" -sev Info

                # Save progress immediately
                $MigrationRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    AppId        = $AppId
                    MultiTenant  = [string]$MultiTenant
                    RedirectUri  = $TargetUrl
                    Status       = 'app_created'
                    CreatedAt    = $Existing.CreatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = ''
                }
                Add-CIPPAzDataTableEntity @MigrationTable -Entity $MigrationRow -Force | Out-Null

                $KV = $env:WEBSITE_DEPLOYMENT_ID
                $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    # Dev mode — store in DevSecrets table
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                    if (-not $Secret) { $Secret = [PSCustomObject]@{} }
                    $Secret | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppId' -Value $AppId -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'SSOMultiTenant' -Value ([string]$MultiTenant) -Force
                    if ($AppSecret) {
                        $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppSecret' -Value $AppSecret -Force
                    }
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
                    Write-Information '[SSO-Setup] Stored SSO credentials in DevSecrets table'
                } else {
                    # Production — store in Key Vault
                    if (-not $VaultName) {
                        throw 'Cannot determine Key Vault name from WEBSITE_DEPLOYMENT_ID'
                    }

                    # Step 2: Store AppId in KV (idempotent — Set overwrites)
                    $ExistingAppIdSecret = $null
                    try {
                        $ExistingAppIdSecret = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop
                    } catch { }

                    if (-not $ExistingAppIdSecret -or $ExistingAppIdSecret -ne $AppId) {
                        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -SecretValue (ConvertTo-SecureString -String $AppId -AsPlainText -Force)
                        Write-Information "[SSO-Setup] Stored SSOAppId in Key Vault"
                    }

                    # Update status
                    $UpdateRow = @{
                        PartitionKey = 'SSO'
                        RowKey       = 'MigrationConfig'
                        Status       = 'appid_stored'
                        LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    }
                    Add-CIPPAzDataTableEntity @MigrationTable -Entity $UpdateRow -Force | Out-Null

                    # Step 3: Store AppSecret in KV
                    if ($AppSecret) {
                        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppSecret' -SecretValue (ConvertTo-SecureString -String $AppSecret -AsPlainText -Force)
                        Write-Information "[SSO-Setup] Stored SSOAppSecret in Key Vault"
                    }

                    # Step 4: Verify TenantID exists in KV (should already be there from SAM setup)
                    $ExistingTenantId = $null
                    try {
                        $ExistingTenantId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'TenantID' -AsPlainText -ErrorAction Stop
                    } catch { }

                    if (-not $ExistingTenantId) {
                        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'TenantID' -SecretValue (ConvertTo-SecureString -String $env:TenantID -AsPlainText -Force)
                        Write-Information "[SSO-Setup] Stored TenantID in Key Vault (was missing)"
                    }

                    # Step 5: Store MultiTenant flag in KV (used for initial EasyAuth setup on startup)
                    Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOMultiTenant' -SecretValue (ConvertTo-SecureString -String ([string]$MultiTenant) -AsPlainText -Force)
                    Write-Information "[SSO-Setup] Stored SSOMultiTenant=$MultiTenant in Key Vault"
                }

                # Mark migration as secrets_stored
                $FinalRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    AppId        = $AppId
                    MultiTenant  = [string]$MultiTenant
                    RedirectUri  = $TargetUrl
                    Status       = 'secrets_stored'
                    CreatedAt    = $Existing.CreatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = ''
                }
                Add-CIPPAzDataTableEntity @MigrationTable -Entity $FinalRow -Force | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration credentials stored for app $AppId" -sev Info
                $Body = @{
                    Results = @{
                        message     = 'CIPP-SSO app created and credentials stored. EasyAuth will be configured automatically on next startup.'
                        appId       = $AppId
                        multiTenant = $MultiTenant
                        severity    = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO setup failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage

                # Save error state so the scheduled task can retry
                $ErrorRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    Status       = 'error'
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = $ErrorMessage.NormalizedError
                }
                try { Add-CIPPAzDataTableEntity @MigrationTable -Entity $ErrorRow -Force | Out-Null } catch { }

                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO setup failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'Update' {
            # Update existing SSO app configuration (e.g. switch single ↔ multi-tenant)
            try {
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                # Fall back to live EasyAuth config if migration table has no entry
                if ((-not $Existing -or -not $Existing.AppId) -and $env:CIPPNG -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
                    $LiveConfig = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $LiveAppId = $LiveConfig.identityProviders.azureActiveDirectory.registration.clientId
                    if ($LiveAppId) {
                        $Existing = [PSCustomObject]@{ AppId = $LiveAppId; Status = 'complete'; CreatedAt = $null }
                    }
                }
                if (-not $Existing -or -not $Existing.AppId) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'No SSO app has been created yet. Use the Create action first.' }
                    break
                }

                $MultiTenant = [bool]($Request.Body.multiTenant)
                $TargetUrl = $Request.Body.targetUrl
                if (-not $TargetUrl) {
                    $TargetUrl = $Request.Headers.origin ?? $Request.Headers.referer?.TrimEnd('/')
                }
                if (-not $TargetUrl) {
                    $TargetUrl = "https://$($env:WEBSITE_HOSTNAME)"
                }

                $SignInAudience = if ($MultiTenant) { 'AzureADMultipleOrgs' } else { 'AzureADMyOrg' }
                $CallbackUri = $TargetUrl.TrimEnd('/') + '/.auth/login/aad/callback'

                # Look up the existing app and patch it
                $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($Existing.AppId)')?`$select=id,appId,web,signInAudience" -NoAuthCheck $true -AsApp $true

                $PatchBody = @{
                    signInAudience = $SignInAudience
                    web            = @{
                        redirectUris          = @($CallbackUri)
                        implicitGrantSettings = @{ enableIdTokenIssuance = $true }
                    }
                } | ConvertTo-Json -Depth 10 -Compress

                New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $PatchBody -type PATCH -NoAuthCheck $true -AsApp $true

                # Update migration table
                $UpdateRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    AppId        = $Existing.AppId
                    MultiTenant  = [string]$MultiTenant
                    RedirectUri  = $TargetUrl
                    Status       = $Existing.Status
                    CreatedAt    = $Existing.CreatedAt
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = ''
                }
                Add-CIPPAzDataTableEntity @MigrationTable -Entity $UpdateRow -Force | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "SSO app updated: multiTenant=$MultiTenant, audience=$SignInAudience" -sev Info

                # Update SSOMultiTenant in KV so initial EasyAuth setup stays in sync
                $KV = $env:WEBSITE_DEPLOYMENT_ID
                $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                    if ($Secret) {
                        $Secret | Add-Member -MemberType NoteProperty -Name 'SSOMultiTenant' -Value ([string]$MultiTenant) -Force
                        Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
                    }
                } elseif ($VaultName) {
                    Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOMultiTenant' -SecretValue (ConvertTo-SecureString -String ([string]$MultiTenant) -AsPlainText -Force)
                }

                # Update EasyAuth ARM config on the App Service (issuer URL + allowed tenants)
                try {
                    Set-CIPPSSOEasyAuth -AppId $Existing.AppId -MultiTenant $MultiTenant -TenantId $env:TenantID
                } catch {
                    Write-Information "[SSO-Update] EasyAuth ARM update skipped (may not be in App Service): $($_.Exception.Message)"
                }

                $Body = @{
                    Results = @{
                        message     = "SSO app updated successfully. Sign-in audience is now $SignInAudience."
                        appId       = $Existing.AppId
                        multiTenant = $MultiTenant
                        severity    = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO update failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO update failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'RotateSecret' {
            # Rotate the client secret for the SSO app
            try {
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                # Fall back to live EasyAuth config if migration table has no entry
                if ((-not $Existing -or -not $Existing.AppId) -and $env:CIPPNG -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
                    $LiveConfig = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $LiveAppId = $LiveConfig.identityProviders.azureActiveDirectory.registration.clientId
                    if ($LiveAppId) {
                        $Existing = [PSCustomObject]@{ AppId = $LiveAppId }
                    }
                }
                if (-not $Existing -or -not $Existing.AppId) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'No SSO app has been created yet.' }
                    break
                }

                # Get the app object ID
                $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($Existing.AppId)')?`$select=id" -NoAuthCheck $true -AsApp $true

                # Create new secret
                $PasswordBody = '{"passwordCredential":{"displayName":"CIPP-SSO-Secret"}}'
                $PasswordResult = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)/addPassword" -body $PasswordBody -type POST -NoAuthCheck $true -AsApp $true
                $NewSecret = $PasswordResult.secretText

                if (-not $NewSecret) {
                    throw 'Failed to create new client secret'
                }

                # Store new secret
                $KV = $env:WEBSITE_DEPLOYMENT_ID
                $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                    if (-not $Secret) { $Secret = [PSCustomObject]@{} }
                    $Secret | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppSecret' -Value $NewSecret -Force
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
                } else {
                    if (-not $VaultName) { throw 'Cannot determine Key Vault name from WEBSITE_DEPLOYMENT_ID' }
                    Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppSecret' -SecretValue (ConvertTo-SecureString -String $NewSecret -AsPlainText -Force)
                }

                # Update last checked
                $UpdateRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = ''
                }
                Add-CIPPAzDataTableEntity @MigrationTable -Entity $UpdateRow -Force | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "SSO app secret rotated for $($Existing.AppId)" -sev Info
                $Body = @{
                    Results = @{
                        message  = 'Client secret rotated successfully. The new secret will be picked up from Key Vault on next restart.'
                        severity = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO secret rotation failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Secret rotation failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'Migrate' {
            # Forced SSO migration. Creates the customer's own CIPP-SSO app,
            # stores credentials in Key Vault, configures EasyAuth, and removes the migration
            # trigger env var. The central migration app (implicit auth, no secret) is replaced
            # by the customer's own app with a proper client secret.
            if (-not $env:CIPP_SSO_MIGRATION_APPID) {
                $Body = @{ Results = @{ message = 'No SSO migration pending.'; severity = 'info' } }
                break
            }

            $MultiTenant = [bool]($Request.Body.multiTenant)
            $TargetUrl = "https://$($env:WEBSITE_HOSTNAME)"

            try {
                # Check if we already have SSO credentials from a previous partial run
                $KV = $env:WEBSITE_DEPLOYMENT_ID
                $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }
                $ExistingAppId = $null

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $DevSecret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                    $ExistingAppId = $DevSecret.SSOAppId
                } elseif ($VaultName) {
                    try { $ExistingAppId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { }
                }

                # Step 1: Create or update the customer's own CIPP-SSO app registration
                $SSOAppParams = @{
                    RedirectUri = $TargetUrl
                    MultiTenant = $MultiTenant
                }
                if ($ExistingAppId) { $SSOAppParams.ExistingAppId = $ExistingAppId }

                $SSOApp = New-CIPPSSOApp @SSOAppParams
                $AppId = $SSOApp.AppId
                $AppSecret = $SSOApp.ClientSecret
                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration: CIPP-SSO app $($SSOApp.State): $AppId" -sev Info

                # Step 2: Store credentials
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                    if (-not $Secret) { $Secret = [PSCustomObject]@{} }
                    $Secret | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value 'SSO' -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppId' -Value $AppId -Force
                    $Secret | Add-Member -MemberType NoteProperty -Name 'SSOMultiTenant' -Value ([string]$MultiTenant) -Force
                    if ($AppSecret) {
                        $Secret | Add-Member -MemberType NoteProperty -Name 'SSOAppSecret' -Value $AppSecret -Force
                    }
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
                    Write-Information '[SSO-Migrate] Stored SSO credentials in DevSecrets table'
                } else {
                    if (-not $VaultName) { throw 'Cannot determine Key Vault name from WEBSITE_DEPLOYMENT_ID' }

                    Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -SecretValue (ConvertTo-SecureString -String $AppId -AsPlainText -Force)
                    if ($AppSecret) {
                        Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppSecret' -SecretValue (ConvertTo-SecureString -String $AppSecret -AsPlainText -Force)
                    }
                    Set-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOMultiTenant' -SecretValue (ConvertTo-SecureString -String ([string]$MultiTenant) -AsPlainText -Force)
                    Write-Information "[SSO-Migrate] Stored SSO credentials in Key Vault ($VaultName)"
                }

                # Step 3: Configure EasyAuth on the App Service
                Set-CIPPSSOEasyAuth -AppId $AppId -MultiTenant $MultiTenant -TenantId $env:TenantID -UseKvReferences

                # Step 4: Remove the migration trigger env var
                Remove-CIPPMigrationAppSetting -SettingName 'CIPP_SSO_MIGRATION_APPID'

                # Step 5: Track in migration table (for audit/status)
                $MigrationRow = @{
                    PartitionKey = 'SSO'
                    RowKey       = 'MigrationConfig'
                    AppId        = $AppId
                    MultiTenant  = [string]$MultiTenant
                    RedirectUri  = $TargetUrl
                    Status       = 'complete'
                    CreatedAt    = (Get-Date).ToUniversalTime().ToString('o')
                    LastChecked  = (Get-Date).ToUniversalTime().ToString('o')
                    LastError    = ''
                    MigratedFrom = 'SWA'
                }
                Add-CIPPAzDataTableEntity @MigrationTable -Entity $MigrationRow -Force | Out-Null

                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration complete: appId=$AppId, multiTenant=$MultiTenant" -sev Info

                # Step 6: Restart to apply EasyAuth
                [Craft.Services.AppLifecycleBridge]::RequestRestart('SSO migration complete — EasyAuth configured with customer CIPP-SSO app')

                $Body = @{
                    Results = @{
                        message     = 'SSO migration complete. Your instance will restart with your own CIPP-SSO app registration. You will be redirected to log in once the instance is back online.'
                        appId       = $AppId
                        multiTenant = $MultiTenant
                        severity    = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO migration failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        default {
            $StatusCode = [HttpStatusCode]::BadRequest
            $Body = @{ Results = "Unknown action: $Action. Use 'Status', 'Create', or 'Update'." }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = $Body
    }
}
