function Get-GraphToken($tenantid, $scope, $AsApp, $AppID, $AppSecret, $refreshToken, $ReturnRefresh, $SkipCache) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }

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
    if (!$tenantid) { $tenantid = $env:TenantID }
    #Get list of tenants that have 'directTenant' set to true
    #get directtenants directly from table, avoid get-tenants due to performance issues
    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $Filter = "PartitionKey eq 'Tenants' and delegatedPrivilegeStatus eq 'directTenant'"
    $ClientType = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter | Where-Object { $_.customerId -eq $tenantid -or $_.defaultDomainName -eq $tenantid }
    if ($tenantid -ne $env:TenantID -and $clientType.delegatedPrivilegeStatus -eq 'directTenant') {
        Write-Host "Using direct tenant refresh token for $($clientType.customerId)"
        $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue
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


    $TokenKey = '{0}-{1}-{2}' -f $tenantid, $scope, $asApp

    try {
        if ($script:AccessTokens.$TokenKey -and [int](Get-Date -UFormat %s -Millisecond 0) -lt $script:AccessTokens.$TokenKey.expires_on -and $SkipCache -ne $true) {
            #Write-Host 'Graph: cached token'
            $AccessToken = $script:AccessTokens.$TokenKey
        } else {
            #Write-Host 'Graph: new token'
            $AccessToken = (Invoke-RestMethod -Method post -Uri "https://login.microsoftonline.com/$($tenantid)/oauth2/v2.0/token" -Body $Authbody -ErrorAction Stop)
            $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $AccessToken.expires_in
            Add-Member -InputObject $AccessToken -NotePropertyName 'expires_on' -NotePropertyValue $ExpiresOn
            if (!$script:AccessTokens) { $script:AccessTokens = [HashTable]::Synchronized(@{}) }
            $script:AccessTokens.$TokenKey = $AccessToken
        }

        if ($ReturnRefresh) { $header = $AccessToken } else { $header = @{ Authorization = "Bearer $($AccessToken.access_token)" } }
        return $header
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
}
