function Get-GraphToken($tenantid, $scope, $AsApp, $AppID, $refreshToken, $ReturnRefresh, $SkipCache) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }
    if (!$env:SetFromProfile) { $CIPPAuth = Get-CIPPAuthentication; Write-Host 'Could not get Refreshtoken from environment variable. Reloading token.' }
    $AuthBody = @{
        client_id     = $env:ApplicationID
        client_secret = $env:ApplicationSecret
        scope         = $Scope
        refresh_token = $env:RefreshToken
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
            refresh_token = $RefreshToken
            scope         = $Scope
            grant_type    = 'refresh_token'
        }
    }

    if (!$tenantid) { $tenantid = $env:TenantID }

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
                GraphErrorCount     = $null
                LastGraphTokenError = $null
                LastGraphError      = $null
                PartitionKey        = 'TenantFailed'
                RowKey              = 'Failed'
            }
        }
        $Tenant.LastGraphError = if ( $_.ErrorDetails.Message) {
            $msg = $_.ErrorDetails.Message | ConvertFrom-Json
            "$($msg.error):$($msg.error_description)"
        } else {
            $_.Exception.message
        }
        $Tenant.GraphErrorCount++

        if (!$donotset) { Update-AzDataTableEntity @TenantsTable -Entity $Tenant }
        throw "Could not get token: $($Tenant.LastGraphError)"
    }
}
