function Get-GraphToken($tenantid, $scope, $AsApp, $AppID, $AppSecret, $refreshToken, $ReturnRefresh, $SkipCache) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }
    if (!$tenantid) { $tenantid = $env:TenantID }

    $UseSharedTokenCache = ($SkipCache -ne $true) -and ($null -ne ('CIPP.CIPPTokenCache' -as [type]))

    # ── Fast path: check shared .NET token cache before any table lookups ──
    if ($UseSharedTokenCache) {
        $CacheClientId = if ($AppID) { [string]$AppID } else { [string]$env:ApplicationID }
        $GrantType = if ($asApp -eq $true -or ($null -ne $AppID -and $null -ne $AppSecret)) { 'client_credentials' } else { 'refresh_token' }
        $SharedTokenCacheKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, [string]$scope, [bool]$asApp, $CacheClientId, $GrantType)
        $SharedCacheEntry = [CIPP.CIPPTokenCache]::Lookup($SharedTokenCacheKey, 120)
        if ($SharedCacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($SharedCacheEntry.TokenPayloadJson)) {
            try {
                $AccessToken = $SharedCacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop
                if ($ReturnRefresh) { return $AccessToken }
                return @{ Authorization = "Bearer $($AccessToken.access_token)" }
            } catch {
                [CIPP.CIPPTokenCache]::Remove($SharedTokenCacheKey)
            }
        }
    }

    # ── Slow path: need a new token — do table lookups + token acquisition ──
    # Acquire per-key lock to prevent thundering herd (multiple runspaces
    # all missing cache and independently fetching the same token).
    $LockAcquired = $false
    if ($UseSharedTokenCache -and $SharedTokenCacheKey) {
        $LockAcquired = [CIPP.CIPPTokenCache]::AcquireLock($SharedTokenCacheKey, 30000)
        if ($LockAcquired) {
            # Double-check: another thread may have stored the token while we waited
            $SharedCacheEntry = [CIPP.CIPPTokenCache]::Lookup($SharedTokenCacheKey, 120)
            if ($SharedCacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($SharedCacheEntry.TokenPayloadJson)) {
                try {
                    $AccessToken = $SharedCacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop
                    [CIPP.CIPPTokenCache]::ReleaseLock($SharedTokenCacheKey)
                    $LockAcquired = $false
                    if ($ReturnRefresh) { return $AccessToken }
                    return @{ Authorization = "Bearer $($AccessToken.access_token)" }
                } catch {
                    [CIPP.CIPPTokenCache]::Remove($SharedTokenCacheKey)
                }
            }
        }
    }
    try {
    if (!$env:SetFromProfile) { $CIPPAuth = Get-CIPPAuthentication; Write-Host 'Could not get Refreshtoken from environment variable. Reloading token.' }
    $ConfigTable = Get-CippTable -tablename 'Config'
    $Filter = "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
    $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter
    #force auth update is appId is not the same as the one in the environment variable.
    if ($AppCache.ApplicationId -and $env:ApplicationID -ne $AppCache.ApplicationId) {
        Write-Host "Setting environment variable ApplicationID to $($AppCache.ApplicationId)"
        $CIPPAuth = Get-CIPPAuthentication
    }
    $refreshToken = $env:RefreshToken
    #Get list of tenants that have 'directTenant' set to true
    #get directtenants directly from table, avoid get-tenants due to performance issues
    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $Filter = "PartitionKey eq 'Tenants' and delegatedPrivilegeStatus eq 'directTenant'"
    $ClientType = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter | Where-Object { $_.customerId -eq $tenantid -or $_.defaultDomainName -eq $tenantid }
    if ($tenantid -ne $env:TenantID -and $clientType.delegatedPrivilegeStatus -eq 'directTenant') {
        Write-Host "Using direct tenant refresh token for $($clientType.customerId)"
        $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue

        if ($null -eq $ClientRefreshToken) {
            # Lazy load the refresh token from Key Vault only when needed
            Write-Host "Fetching refresh token for direct tenant $($clientType.customerId) from Key Vault"
            try {
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    # Development environment - get from table storage
                    $Table = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-AzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                    $secretname = $clientType.customerId -replace '-', '_'
                    if ($Secret.$secretname) {
                        Set-Item -Path "env:\$($clientType.customerId)" -Value $Secret.$secretname -Force
                        $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue
                    }
                } else {
                    # Production environment - get from Key Vault
                    $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
                    $secret = Get-CippKeyVaultSecret -VaultName $keyvaultname -Name $clientType.customerId -AsPlainText -ErrorAction Stop
                    if ($secret) {
                        Set-Item -Path "env:\$($clientType.customerId)" -Value $secret -Force
                        $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-Host "Failed to retrieve refresh token for direct tenant $($clientType.customerId): $($_.Exception.Message)"
            }
        }

        $refreshToken = $ClientRefreshToken.Value
    }

    $AuthBody = @{
        client_id     = $env:ApplicationID
        client_secret = $env:ApplicationSecret
        scope         = $Scope
        refresh_token = $refreshToken
        grant_type    = 'refresh_token'
    }
    if ($asApp -eq $true) {
        $AuthBody = @{
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            scope         = $Scope
            grant_type    = 'client_credentials'
        }
    }

    if ($null -ne $AppID -and $null -ne $refreshToken) {
        $AuthBody = @{
            client_id     = $appid
            refresh_token = $refreshToken
            scope         = $Scope
            grant_type    = 'refresh_token'
        }
    }

    if ($null -ne $AppID -and $null -ne $AppSecret) {
        $AuthBody = @{
            client_id     = $AppID
            client_secret = $AppSecret
            scope         = $Scope
            grant_type    = 'client_credentials'
        }
    }

    # Rebuild cache key after credential loading (env vars may have been set by Get-CIPPAuthentication)
    if ($UseSharedTokenCache) {
        $CacheClientId = if ($AppID) { [string]$AppID } else { [string]$env:ApplicationID }
        $GrantType = if ($asApp -eq $true -or ($null -ne $AppID -and $null -ne $AppSecret)) { 'client_credentials' } else { 'refresh_token' }
        $SharedTokenCacheKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, [string]$scope, [bool]$asApp, $CacheClientId, $GrantType)
    }

    try {
        $AccessToken = (Invoke-CIPPRestMethod -Method post -Uri "https://login.microsoftonline.com/$($tenantid)/oauth2/v2.0/token" -Body $Authbody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop)
        if ($null -eq $AccessToken.expires_on -and $AccessToken.expires_in) {
            $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $AccessToken.expires_in
            Add-Member -InputObject $AccessToken -NotePropertyName 'expires_on' -NotePropertyValue $ExpiresOn -Force
        }

        if ($UseSharedTokenCache -and $SharedTokenCacheKey) {
            try {
                $TokenPayloadJson = $AccessToken | ConvertTo-Json -Depth 20 -Compress
                [CIPP.CIPPTokenCache]::Store($SharedTokenCacheKey, $TokenPayloadJson, [int64]$AccessToken.expires_on)
            } catch {
                # Ignore shared cache write failures
            }
        }

        if ($ReturnRefresh) { return $AccessToken }
        return @{ Authorization = "Bearer $($AccessToken.access_token)" }
    } catch {
        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant.RowKey) {
            $donotset = $true
            $Tenant = [pscustomobject]@{
                GraphErrorCount     = 0
                LastGraphTokenError = ''
                LastGraphError      = ''
                PartitionKey        = 'TenantFailed'
                RowKey              = 'Failed'
            }
        }
        $Tenant.LastGraphError = if ( $_.ErrorDetails.Message) {
            if (Test-Json $_.ErrorDetails.Message -ErrorAction SilentlyContinue) {
                $msg = $_.ErrorDetails.Message | ConvertFrom-Json
                "$($msg.error):$($msg.error_description)"
            } else {
                "$($_.ErrorDetails.Message)"
            }
        } else {
            $_.Exception.Message
        }
        $Tenant.GraphErrorCount++

        if (!$donotset) { Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant }
        throw "Could not get token: $($Tenant.LastGraphError)"
    }
    } finally {
        # Always release the per-key lock if we acquired it
        if ($LockAcquired -and $SharedTokenCacheKey) {
            [CIPP.CIPPTokenCache]::ReleaseLock($SharedTokenCacheKey)
        }
    }
}
