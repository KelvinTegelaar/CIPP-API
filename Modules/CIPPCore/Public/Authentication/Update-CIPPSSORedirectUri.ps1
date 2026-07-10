function Update-CIPPSSORedirectUri {
    <#
    .SYNOPSIS
    Ensures the CIPP-SSO app registration includes redirect URIs for all bound hostnames
    and that signInAudience matches the stored multi-tenant flag.

    .DESCRIPTION
    Reads the stored SSO AppId and MultiTenant flag from Key Vault (or DevSecrets table
    in dev mode), then:
    1. Queries ARM for all hostnames bound to the App Service (custom domains + default).
    2. Ensures the SSO app's web.redirectUris includes a callback URI for each hostname.
    3. Verifies and patches signInAudience on the app reg if it doesn't match the stored
       multi-tenant flag (AzureADMyOrg for single-tenant, AzureADMultipleOrgs for multi).
    #>
    [CmdletBinding()]
    param()

    $CurrentHost = $env:WEBSITE_HOSTNAME
    if (-not $CurrentHost) {
        Write-Information '[SSO-Redirect] WEBSITE_HOSTNAME not set, skipping redirect URI update'
        return
    }

    # Resolve the stored SSO AppId and MultiTenant flag
    $SSOAppId = $null
    $SSOMultiTenant = $false
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        try {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
            $SSOAppId = $Secret.SSOAppId
            $SSOMultiTenant = $Secret.SSOMultiTenant -eq 'True'
        } catch { }
    } else {
        $VaultName = Get-CippKeyVaultName
        if ($VaultName) {
            try {
                $SSOAppId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop
            } catch { }
            try {
                $mtVal = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOMultiTenant' -AsPlainText -ErrorAction Stop
                $SSOMultiTenant = $mtVal -eq 'True'
            } catch { }
        }
    }

    if (-not $SSOAppId) {
        Write-Information '[SSO-Redirect] No SSO AppId found, skipping redirect URI update'
        return
    }

    # Discover all bound hostnames via ARM (custom domains + default)
    $AllHostnames = @($CurrentHost)
    try {
        $SiteName = $env:WEBSITE_SITE_NAME
        $ResourceGroup = $env:WEBSITE_RESOURCE_GROUP
        $SubscriptionId = if ($env:WEBSITE_OWNER_NAME) { ($env:WEBSITE_OWNER_NAME -split '\+')[0] } else { $null }

        if ($SiteName -and $ResourceGroup -and $SubscriptionId -and $env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
            $TokenUri = "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01"
            $TokenResponse = Invoke-RestMethod -Uri $TokenUri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER } -Method Get
            $ArmToken = $TokenResponse.access_token

            $SiteUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$SiteName`?api-version=2024-11-01"
            $SiteResponse = Invoke-RestMethod -Uri $SiteUri -Headers @{ Authorization = "Bearer $ArmToken" } -Method Get

            if ($SiteResponse.properties.hostNames) {
                $AllHostnames = @($SiteResponse.properties.hostNames)
                Write-Information "[SSO-Redirect] Discovered hostnames from ARM: $($AllHostnames -join ', ')"
            }
        }
    } catch {
        Write-Information "[SSO-Redirect] ARM hostname discovery failed (using WEBSITE_HOSTNAME only): $($_.Exception.Message)"
    }

    # Build required redirect URIs from all hostnames
    $RequiredUris = foreach ($Hostname in $AllHostnames) {
        "https://$Hostname/.auth/login/aad/callback"
    }

    try {
        $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$SSOAppId')?`$select=id,web,signInAudience" -NoAuthCheck $true -AsApp $true
        $ExistingUris = @($AppResponse.web.redirectUris)

        # Determine which URIs are missing
        $MissingUris = $RequiredUris | Where-Object { $_ -notin $ExistingUris }

        # Determine the expected signInAudience
        $ExpectedAudience = if ($SSOMultiTenant) { 'AzureADMultipleOrgs' } else { 'AzureADMyOrg' }
        $AudienceMismatch = $AppResponse.signInAudience -ne $ExpectedAudience

        if ($MissingUris.Count -eq 0 -and -not $AudienceMismatch) {
            Write-Information '[SSO-Redirect] All redirect URIs present and signInAudience correct'
            return
        }

        # Patch redirect URIs and signInAudience as separate requests. A tenant app-management
        # policy can reject an audience change (e.g. downgrading a multi-tenant app to
        # single-tenant fails with "SigninAudienceRestrictions with restricted mode can be
        # configured only on multi-tenants apps"). Sending them together would let that
        # rejection also drop the redirect URI additions, which are needed for sign-in.
        if ($MissingUris.Count -gt 0) {
            $UpdatedUris = [System.Collections.Generic.List[string]]::new()
            $ExistingUris | ForEach-Object { $UpdatedUris.Add($_) }
            $MissingUris | ForEach-Object { $UpdatedUris.Add($_) }
            $UriBody = @{ web = @{ redirectUris = $UpdatedUris } } | ConvertTo-Json -Depth 5
            New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $UriBody -type PATCH -NoAuthCheck $true -AsApp $true
            Write-Information "[SSO-Redirect] Added redirect URIs: $($MissingUris -join ', ')"
            Write-LogMessage -API 'SSO-Redirect' -message "Added redirect URIs: $($MissingUris -join ', ')" -sev Info
        }

        if ($AudienceMismatch) {
            Write-Information "[SSO-Redirect] Correcting signInAudience: $($AppResponse.signInAudience) -> $ExpectedAudience"
            try {
                $AudienceBody = @{ signInAudience = $ExpectedAudience } | ConvertTo-Json -Compress
                New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $AudienceBody -type PATCH -NoAuthCheck $true -AsApp $true
                Write-LogMessage -API 'SSO-Redirect' -message "Updated signInAudience to $ExpectedAudience (multiTenant=$SSOMultiTenant)" -sev Info
            } catch {
                # Non-fatal: a tenant app-management policy is blocking the audience change.
                # EasyAuth issuer validation already enforces the effective tenant scope, so the
                # app registration can stay as-is. Log at Info so warmup doesn't spam warnings.
                Write-Information "[SSO-Redirect] signInAudience change to $ExpectedAudience was rejected by tenant policy (leaving app reg as $($AppResponse.signInAudience)): $($_.Exception.Message)"
            }
        }
    } catch {
        Write-LogMessage -API 'SSO-Redirect' -message "Failed to update SSO app registration: $_" -LogData (Get-CippException -Exception $_) -sev Warning
    }
}
