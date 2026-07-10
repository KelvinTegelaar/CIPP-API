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

    # Resolve the redirect URI once for any action that needs it
    $ResolveTargetUrl = {
        param($BodyUrl)
        if ($BodyUrl) { return $BodyUrl }
        $FromHeader = $Request.Headers.origin ?? $Request.Headers.referer?.TrimEnd('/')
        if ($FromHeader) { return $FromHeader }
        return "https://$($env:WEBSITE_HOSTNAME)"
    }

    # Save a row to the migration table while preserving fields that aren't being updated
    $SaveMigrationRow = {
        param([hashtable]$Updates)
        $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
        $Row = @{
            PartitionKey = 'SSO'
            RowKey       = 'MigrationConfig'
        }
        # Preserve existing fields
        if ($Existing) {
            foreach ($Prop in $Existing.PSObject.Properties) {
                if ($Prop.Name -notin @('PartitionKey', 'RowKey', 'Timestamp', 'ETag', 'odata.etag')) {
                    $Row[$Prop.Name] = $Prop.Value
                }
            }
        }
        # Apply updates on top
        foreach ($Key in $Updates.Keys) { $Row[$Key] = $Updates[$Key] }
        $Row['LastChecked'] = (Get-Date).ToUniversalTime().ToString('o')
        Add-CIPPAzDataTableEntity @MigrationTable -Entity $Row -Force | Out-Null
    }

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

                        # Surface migration-table state for the live AppId so the UI can offer Repair
                        # if the migration row matches the live ClientId AND is in a partial state.
                        # If the migration row is stale (different AppId), defer to live EasyAuth = complete.
                        $Migration = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                        $MigrationMatches = $Migration -and $Migration.AppId -and $Migration.AppId -eq $ClientId
                        $MigrationStatus = if ($MigrationMatches) { $Migration.Status } else { 'complete' }
                        $MigrationError = if ($MigrationMatches) { $Migration.LastError } else { '' }
                        $MigrationCanRepair = $MigrationMatches -and ($Migration.Status -in @('error', 'app_created', 'appid_stored'))

                        $Body = @{
                            Results = @{
                                configured     = $true
                                status         = $MigrationStatus
                                appId          = $ClientId
                                multiTenant    = $IsMultiTenant
                                tenantId       = $IssuerTenantId
                                issuer         = $Issuer
                                audiences      = $AllowedAudiences
                                allowedApps    = $AllowedApps
                                excludedPaths  = $ExcludedPaths
                                easyAuthActive = $true
                                lastError      = $MigrationError
                                canRepair      = [bool]$MigrationCanRepair
                            }
                        }
                    } else {
                        # EasyAuth not active — fall through to the migration table so partial-state appId/error still surfaces
                        $Migration = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                        if ($Migration) {
                            $Body = @{
                                Results = @{
                                    configured     = $true
                                    status         = $Migration.Status
                                    appId          = $Migration.AppId
                                    multiTenant    = [bool]($Migration.MultiTenant -eq 'true' -or $Migration.MultiTenant -eq 'True')
                                    createdAt      = $Migration.CreatedAt
                                    lastChecked    = $Migration.LastChecked
                                    lastError      = $Migration.LastError
                                    easyAuthActive = $false
                                    canRepair      = [bool]($Migration.AppId -and ($Migration.Status -in @('error', 'app_created', 'appid_stored')))
                                }
                            }
                        } else {
                            $Body = @{ Results = @{ configured = $false; status = 'none'; easyAuthActive = $false } }
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -message "Failed to parse EasyAuth config: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    $Body = @{ Results = @{ configured = $false; status = 'error'; lastError = $ErrorMessage.NormalizedError } }
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
                                multiTenant = [bool]($Migration.MultiTenant -eq 'true' -or $Migration.MultiTenant -eq 'True')
                                createdAt   = $Migration.CreatedAt
                                lastChecked = $Migration.LastChecked
                                lastError   = $Migration.LastError
                                canRepair   = [bool]($Migration.AppId -and ($Migration.Status -in @('error', 'app_created', 'appid_stored')))
                            }
                        }
                    } else {
                        $Body = @{ Results = @{ configured = $false; status = 'none' } }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -message "Failed to get SSO status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    $Body = @{ Results = @{ configured = $false; status = 'error'; lastError = $ErrorMessage.NormalizedError } }
                }
            }
        }

        'Create' {
            $MultiTenant = [bool]($Request.Body.multiTenant)
            $TargetUrl = & $ResolveTargetUrl $Request.Body.targetUrl

            try {
                # Check if already provisioned
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                if ($Existing -and $Existing.Status -in @('secrets_stored', 'complete')) {
                    $Body = @{
                        Results = @{
                            message  = 'SSO app is already provisioned. Use Repair to refresh the secret or Recreate to start over.'
                            appId    = $Existing.AppId
                            severity = 'info'
                        }
                    }
                    break
                }

                # Pick up from where we left off if we have a partial record
                $ExistingAppId = $Existing.AppId

                # --- Step 1: Create or update the app registration (no secret yet) ---
                $SSOAppParams = @{
                    RedirectUri = $TargetUrl
                    MultiTenant = $MultiTenant
                }
                if ($ExistingAppId) { $SSOAppParams.ExistingAppId = $ExistingAppId }

                $SSOApp = New-CIPPSSOApp @SSOAppParams
                $AppId = $SSOApp.AppId
                $ObjectId = $SSOApp.ObjectId
                Write-LogMessage -API $APIName -headers $Headers -message "CIPP-SSO app $($SSOApp.State): $AppId" -sev Info

                # --- Step 2: Persist AppId immediately so a later secret failure doesn't lose it ---
                & $SaveMigrationRow @{
                    AppId       = $AppId
                    ObjectId    = $ObjectId
                    MultiTenant = [string]$MultiTenant
                    RedirectUri = $TargetUrl
                    Status      = 'app_created'
                    CreatedAt   = $Existing.CreatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
                    LastError   = ''
                }

                # --- Step 3: Store AppId + MultiTenant flag in KV (still no secret) ---
                try {
                    Set-CIPPSSOStoredCredentials -AppId $AppId -MultiTenant $MultiTenant
                    Write-Information '[SSO-Setup] AppId and MultiTenant flag stored'

                    # Best-effort: stash TenantID in KV if missing (was previously inline)
                    if (-not ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true')) {
                        $VaultName = Get-CippKeyVaultName
                        if ($VaultName -and $env:TenantID) {
                            $ExistingTenantId = $null
                            try { $ExistingTenantId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'TenantID' -AsPlainText -ErrorAction Stop } catch { }
                            if (-not $ExistingTenantId) {
                                Set-CippKeyVaultSecret -VaultName $VaultName -Name 'TenantID' -SecretValue (ConvertTo-SecureString -String $env:TenantID -AsPlainText -Force)
                                Write-Information '[SSO-Setup] Stored TenantID in Key Vault (was missing)'
                            }
                        }
                    }

                    & $SaveMigrationRow @{ Status = 'appid_stored' }
                } catch {
                    $StoreError = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -headers $Headers -message "Failed to store SSO AppId: $($StoreError.NormalizedError)" -sev Error -LogData $StoreError
                    & $SaveMigrationRow @{ Status = 'error'; LastError = "Failed to store AppId: $($StoreError.NormalizedError)" }
                    throw
                }

                # --- Step 4: Create the client secret (may legitimately fail; Repair can resume) ---
                $AppSecret = $null
                try {
                    $AppSecret = Add-CIPPSSOAppSecret -ObjectId $ObjectId
                } catch {
                    $SecretError = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -headers $Headers -message "SSO secret creation failed (AppId preserved, use Repair): $($SecretError.NormalizedError)" -sev Error -LogData $SecretError
                    & $SaveMigrationRow @{ Status = 'error'; LastError = $SecretError.NormalizedError }

                    $StatusCode = [HttpStatusCode]::OK
                    $Body = @{
                        Results = @{
                            message  = "SSO app created (AppId: $AppId) but client secret creation failed. Use Repair to retry — the AppId is preserved."
                            appId    = $AppId
                            severity = 'warning'
                            canRepair = $true
                            lastError = $SecretError.NormalizedError
                        }
                    }
                    break
                }

                # --- Step 5: Store the secret ---
                try {
                    Set-CIPPSSOStoredCredentials -AppSecret $AppSecret
                    Write-Information '[SSO-Setup] AppSecret stored'
                } catch {
                    $StoreError = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -headers $Headers -message "Failed to store SSO secret: $($StoreError.NormalizedError)" -sev Error -LogData $StoreError
                    & $SaveMigrationRow @{ Status = 'error'; LastError = "Secret created but storage failed: $($StoreError.NormalizedError)" }
                    throw
                }

                # --- Step 6: Mark migration as secrets_stored ---
                & $SaveMigrationRow @{ Status = 'secrets_stored'; LastError = '' }

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

                # Migration row already has the most accurate Status/LastError from the inner catches; only write if nothing was written
                try {
                    $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                    if (-not $Existing -or $Existing.Status -ne 'error') {
                        & $SaveMigrationRow @{ Status = 'error'; LastError = $ErrorMessage.NormalizedError }
                    }
                } catch { }

                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO setup failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'Repair' {
            # Picks up from any partial state — adds a new secret to the existing AppId and stores it.
            try {
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue

                # Fall back to live EasyAuth config when the migration table is empty (e.g. forced-migration flow)
                if ((-not $Existing -or -not $Existing.AppId) -and $env:CIPPNG -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
                    $LiveConfig = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $LiveAppId = $LiveConfig.identityProviders.azureActiveDirectory.registration.clientId
                    if ($LiveAppId) {
                        $Existing = [PSCustomObject]@{ AppId = $LiveAppId; MultiTenant = 'false' }
                    }
                }

                if (-not $Existing -or -not $Existing.AppId) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'No SSO app to repair. Use Create to provision one.' }
                    break
                }

                $AppId = $Existing.AppId

                # Look up the ObjectId — we may have stored it, or we need to fetch it from Graph
                $ObjectId = $Existing.ObjectId
                if (-not $ObjectId) {
                    $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')?`$select=id" -NoAuthCheck $true -AsApp $true
                    $ObjectId = $AppResponse.id
                }

                # Create a fresh secret on the existing app
                $AppSecret = Add-CIPPSSOAppSecret -ObjectId $ObjectId

                # Persist it
                $MultiTenantFlag = [bool]($Existing.MultiTenant -eq 'true' -or $Existing.MultiTenant -eq 'True')
                Set-CIPPSSOStoredCredentials -AppId $AppId -AppSecret $AppSecret -MultiTenant $MultiTenantFlag

                & $SaveMigrationRow @{
                    AppId       = $AppId
                    ObjectId    = $ObjectId
                    MultiTenant = [string]$MultiTenantFlag
                    Status      = 'secrets_stored'
                    LastError   = ''
                }

                Write-LogMessage -API $APIName -headers $Headers -message "SSO app repaired — new secret stored for $AppId" -sev Info
                $Body = @{
                    Results = @{
                        message  = 'CIPP-SSO repaired. A new client secret was created and stored. EasyAuth will pick it up on next restart.'
                        appId    = $AppId
                        severity = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO repair failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                try { & $SaveMigrationRow @{ Status = 'error'; LastError = $ErrorMessage.NormalizedError } } catch { }
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO repair failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'Recreate' {
            # Clears the migration record so the next Create provisions a brand new app
            # (the previous app is left orphaned in the tenant — admin can delete manually if desired).
            try {
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                $PreviousAppId = $Existing.AppId

                if ($Existing) {
                    Remove-AzDataTableEntity @MigrationTable -Entity $Existing -Force | Out-Null
                    Write-LogMessage -API $APIName -headers $Headers -message "SSO migration record cleared (previous AppId: $PreviousAppId). Use Create to provision a new app." -sev Info
                }

                $Body = @{
                    Results = @{
                        message        = if ($PreviousAppId) {
                            "Previous SSO record cleared. The old app registration ($PreviousAppId) is still in your tenant — delete it manually from Entra if you no longer want it. Click Create SSO App to provision a fresh one."
                        } else {
                            'No SSO record to clear. Click Create SSO App to provision a new app.'
                        }
                        previousAppId  = $PreviousAppId
                        severity       = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "SSO recreate failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO recreate failed: $($ErrorMessage.NormalizedError)" }
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
                $TargetUrl = & $ResolveTargetUrl $Request.Body.targetUrl

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
                & $SaveMigrationRow @{
                    AppId       = $Existing.AppId
                    MultiTenant = [string]$MultiTenant
                    RedirectUri = $TargetUrl
                    LastError   = ''
                }

                Write-LogMessage -API $APIName -headers $Headers -message "SSO app updated: multiTenant=$MultiTenant, audience=$SignInAudience" -sev Info

                # Update SSOMultiTenant in KV so initial EasyAuth setup stays in sync
                Set-CIPPSSOStoredCredentials -MultiTenant $MultiTenant

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
                $ObjectId = $Existing.ObjectId
                if (-not $ObjectId) {
                    $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($Existing.AppId)')?`$select=id" -NoAuthCheck $true -AsApp $true
                    $ObjectId = $AppResponse.id
                }

                # Create new secret using the same retry helper
                $NewSecret = Add-CIPPSSOAppSecret -ObjectId $ObjectId

                # Store new secret
                Set-CIPPSSOStoredCredentials -AppSecret $NewSecret

                & $SaveMigrationRow @{ LastError = '' }

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
                # Check if we have an in-progress migration record (so secret-only retries reuse the AppId)
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                $ExistingAppId = $Existing.AppId

                # Also check KV / DevSecrets in case a previous partial run stored the AppId there
                if (-not $ExistingAppId) {
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                        $DevSecret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
                        $ExistingAppId = $DevSecret.SSOAppId
                    } else {
                        $VaultName = Get-CippKeyVaultName
                        if ($VaultName) {
                            try { $ExistingAppId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { }
                        }
                    }
                }

                # --- Step 1: Create or update the customer's own CIPP-SSO app registration (no secret yet) ---
                $SSOAppParams = @{
                    RedirectUri = $TargetUrl
                    MultiTenant = $MultiTenant
                }
                if ($ExistingAppId) { $SSOAppParams.ExistingAppId = $ExistingAppId }

                $SSOApp = New-CIPPSSOApp @SSOAppParams
                $AppId = $SSOApp.AppId
                $ObjectId = $SSOApp.ObjectId
                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration: CIPP-SSO app $($SSOApp.State): $AppId" -sev Info

                # --- Step 2: Persist AppId immediately ---
                & $SaveMigrationRow @{
                    AppId       = $AppId
                    ObjectId    = $ObjectId
                    MultiTenant = [string]$MultiTenant
                    RedirectUri = $TargetUrl
                    Status      = 'app_created'
                    CreatedAt   = $Existing.CreatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
                    MigratedFrom = 'SWA'
                    LastError   = ''
                }
                Set-CIPPSSOStoredCredentials -AppId $AppId -MultiTenant $MultiTenant
                & $SaveMigrationRow @{ Status = 'appid_stored' }

                # --- Step 3: Create the client secret (with retry) ---
                try {
                    $AppSecret = Add-CIPPSSOAppSecret -ObjectId $ObjectId
                } catch {
                    $SecretError = Get-CippException -Exception $_
                    Write-LogMessage -API $APIName -headers $Headers -message "SSO migration secret creation failed (AppId preserved, use Repair): $($SecretError.NormalizedError)" -sev Error -LogData $SecretError
                    & $SaveMigrationRow @{ Status = 'error'; LastError = $SecretError.NormalizedError }
                    $StatusCode = [HttpStatusCode]::InternalServerError
                    $Body = @{ Results = "SSO migration failed at secret creation: $($SecretError.NormalizedError) — use Repair from the SSO settings page once you can sign in." }
                    break
                }

                # --- Step 4: Store the secret ---
                Set-CIPPSSOStoredCredentials -AppSecret $AppSecret

                # --- Step 5: Configure EasyAuth on the App Service ---
                Set-CIPPSSOEasyAuth -AppId $AppId -MultiTenant $MultiTenant -TenantId $env:TenantID -UseKvReferences

                # --- Step 6: Remove the migration trigger env var ---
                Remove-CIPPMigrationAppSetting -SettingName 'CIPP_SSO_MIGRATION_APPID'

                # --- Step 7: Mark complete ---
                & $SaveMigrationRow @{ Status = 'complete'; LastError = '' }

                Write-LogMessage -API $APIName -headers $Headers -message "SSO migration complete: appId=$AppId, multiTenant=$MultiTenant" -sev Info

                # --- Step 8: Restart to apply EasyAuth ---
                Request-CIPPRestart -Reason 'SSO migration complete — EasyAuth configured with customer CIPP-SSO app'

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
                try { & $SaveMigrationRow @{ Status = 'error'; LastError = $ErrorMessage.NormalizedError } } catch { }
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "SSO migration failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        'ManualConfigure' {
            # Manually set the SSO AppId / client secret / multi-tenant flag directly in Key Vault.
            # Used to rotate the secret by hand or repoint EasyAuth at a different app registration
            # without the automated Create/Repair flow. Credentials are read from KV at startup,
            # so the instance must be restarted for the change to take effect.
            try {
                $AppId = $Request.Body.appId
                $AppSecret = $Request.Body.appSecret
                $MultiTenant = [bool]($Request.Body.multiTenant)

                # Validate AppId — must be a GUID
                $ParsedGuid = [System.Guid]::Empty
                if ([string]::IsNullOrWhiteSpace($AppId) -or -not [System.Guid]::TryParse($AppId.Trim(), [ref]$ParsedGuid)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'A valid Application (client) ID is required.' }
                    break
                }
                $AppId = $ParsedGuid.ToString()

                if ([string]::IsNullOrWhiteSpace($AppSecret)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'A client secret is required.' }
                    break
                }

                # Persist to Key Vault (or the DevSecrets table in dev mode)
                Set-CIPPSSOStoredCredentials -AppId $AppId -AppSecret $AppSecret -MultiTenant $MultiTenant

                # Update the migration table so the Status page reflects the manual config.
                # Clear ObjectId — it belonged to the previous app registration and would be stale
                # if the AppId was changed. Repair/RotateSecret re-fetch it by AppId when missing.
                $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
                & $SaveMigrationRow @{
                    AppId        = $AppId
                    ObjectId     = ''
                    MultiTenant  = [string]$MultiTenant
                    Status       = 'secrets_stored'
                    CreatedAt    = $Existing.CreatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
                    ManualConfig = 'true'
                    LastError    = ''
                }

                Write-LogMessage -API $APIName -headers $Headers -message "SSO credentials manually configured for app $AppId (multiTenant=$MultiTenant)" -sev Info

                $IsCippNg = [bool]$env:CIPPNG
                $Message = if ($IsCippNg) {
                    'SSO credentials saved to Key Vault. Restart the instance to apply the new configuration.'
                } else {
                    'SSO credentials saved to Key Vault successfully.'
                }

                $Body = @{
                    Results = @{
                        message         = $Message
                        appId           = $AppId
                        multiTenant     = $MultiTenant
                        requiresRestart = $IsCippNg
                        isCippNg        = $IsCippNg
                        severity        = 'success'
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Manual SSO configuration failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Body = @{ Results = "Manual SSO configuration failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        default {
            $StatusCode = [HttpStatusCode]::BadRequest
            $Body = @{ Results = "Unknown action: $Action. Use 'Status', 'Create', 'Repair', 'Recreate', 'Update', 'RotateSecret', 'ManualConfigure', or 'Migrate'." }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = $Body
    }
}
