function Invoke-ExecListAppId {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    Get-CIPPAuthentication
    $ResponseURL = "$(($Request.headers.'x-ms-original-url').replace('/api/ExecListAppId','/api/ExecSAMSetup'))"
    #make sure we get the very latest version of the appid from kv:
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        $env:ApplicationID = $Secret.ApplicationID
        $env:TenantID = $Secret.TenantID
    } else {
        $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        try {
            $env:ApplicationID = (Get-CippKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'ApplicationID')
            $env:TenantID = (Get-CippKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'TenantID')
            Write-Information "Retrieving secrets from KeyVault: $keyvaultname. The AppId is $($env:ApplicationID) and the TenantId is $($env:TenantID)"
        } catch {
            Write-Information "Retrieving secrets from KeyVault: $keyvaultname. The AppId is $($env:ApplicationID) and the TenantId is $($env:TenantID)"
            Write-LogMessage -message "Failed to retrieve secrets from KeyVault: $keyvaultname" -LogData (Get-CippException -Exception $_) -Sev 'Error'
            $env:ApplicationID = (Get-CippException -Exception $_)
            $env:TenantID = (Get-CippException -Exception $_)
        }
    }

    # Get organization info and authenticated user using bulk request
    $AuthenticatedUserDisplayName = $null
    $AuthenticatedUserPrincipalName = $null
    $OrgInfo = $null
    try {
        $BulkRequests = @(
            @{
                id     = 'organization'
                url    = '/organization?$select=displayName,partnerTenantType'
                method = 'GET'
            },
            @{
                id     = 'me'
                url    = '/me?$select=displayName,userPrincipalName'
                method = 'GET'
            }
            @{
                id     = 'application'
                url    = "/applications(appId='$($env:ApplicationID)')?`$select=id,web"
                method = 'GET'
            }
        )

        $BulkResponse = New-GraphBulkRequest -Requests $BulkRequests -tenantid $env:TenantID -NoAuthCheck $true
        $OrgResponse = $BulkResponse | Where-Object { $_.id -eq 'organization' }
        $MeResponse = $BulkResponse | Where-Object { $_.id -eq 'me' }
        $AppResponse = $BulkResponse | Where-Object { $_.id -eq 'application' }
        if ($MeResponse.body) {
            $AuthenticatedUserDisplayName = $MeResponse.body.displayName
            $AuthenticatedUserPrincipalName = $MeResponse.body.userPrincipalName
        }
        if ($OrgResponse.body.value -and $OrgResponse.body.value.Count -gt 0) {
            $OrgInfo = $OrgResponse.body.value[0]
        }

        if ($AppResponse.body) {
            $AppWeb = $AppResponse.body.web
            if ($AppWeb.redirectUris) {
                # construct new redirect uri with current
                $URL = ($Request.headers.'x-ms-original-url').split('/api') | Select-Object -First 1
                $NewRedirectUri = "$($URL)/authredirect"
                if ($AppWeb.redirectUris -notcontains $NewRedirectUri) {
                    try {
                        $RedirectUris = [system.collections.generic.list[string]]::new()
                        $AppWeb.redirectUris | ForEach-Object { $RedirectUris.Add($_) }
                        $RedirectUris.Add($NewRedirectUri)
                        $AppUpdateBody = @{
                            web = @{
                                redirectUris = $RedirectUris
                            }
                        } | ConvertTo-Json -Depth 10
                        Invoke-GraphRequest -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$($AppResponse.body.id)" -Body $AppUpdateBody -tenantid $env:TenantID -NoAuthCheck $true
                        Write-LogMessage -message "Updated redirect URIs for application $($env:ApplicationID) to include $NewRedirectUri" -Sev 'Info'
                    } catch {
                        Write-LogMessage -message "Failed to update redirect URIs for application $($env:ApplicationID)" -LogData (Get-CippException -Exception $_) -sev 'Warn'
                    }
                }
            }
        }
    } catch {
        Write-LogMessage -message 'Failed to retrieve organization info and authenticated user' -LogData (Get-CippException -Exception $_) -sev 'Warn'
    }

    $Results = @{
        applicationId                  = $env:ApplicationID
        tenantId                       = $env:TenantID
        orgName                        = $OrgInfo.displayName
        authenticatedUserDisplayName   = $AuthenticatedUserDisplayName
        authenticatedUserPrincipalName = $AuthenticatedUserPrincipalName
        isPartnerTenant                = !!$OrgInfo.partnerTenantType
        partnerTenantType              = $OrgInfo.partnerTenantType
        refreshUrl                     = "https://login.microsoftonline.com/$env:TenantID/oauth2/v2.0/authorize?client_id=$env:ApplicationID&response_type=code&redirect_uri=$ResponseURL&response_mode=query&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default+offline_access+profile+openid&state=1&prompt=select_account"
    }
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    }

}
