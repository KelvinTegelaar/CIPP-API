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
        $KV = $env:WEBSITE_DEPLOYMENT_ID
        $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }
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

        # Build patch body
        $PatchBody = @{}

        if ($MissingUris.Count -gt 0) {
            $UpdatedUris = [System.Collections.Generic.List[string]]::new()
            $ExistingUris | ForEach-Object { $UpdatedUris.Add($_) }
            $MissingUris | ForEach-Object { $UpdatedUris.Add($_) }
            $PatchBody.web = @{ redirectUris = $UpdatedUris }
        }

        if ($AudienceMismatch) {
            $PatchBody.signInAudience = $ExpectedAudience
            Write-Information "[SSO-Redirect] Correcting signInAudience: $($AppResponse.signInAudience) -> $ExpectedAudience"
        }

        $Body = $PatchBody | ConvertTo-Json -Depth 5
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $Body -type PATCH -NoAuthCheck $true -AsApp $true

        if ($MissingUris.Count -gt 0) {
            Write-Information "[SSO-Redirect] Added redirect URIs: $($MissingUris -join ', ')"
            Write-LogMessage -API 'SSO-Redirect' -message "Added redirect URIs: $($MissingUris -join ', ')" -sev Info
        }
        if ($AudienceMismatch) {
            Write-LogMessage -API 'SSO-Redirect' -message "Updated signInAudience to $ExpectedAudience (multiTenant=$SSOMultiTenant)" -sev Info
        }
    } catch {
        Write-LogMessage -API 'SSO-Redirect' -message "Failed to update SSO app registration: $_" -LogData (Get-CippException -Exception $_) -sev Warning
    }
}
