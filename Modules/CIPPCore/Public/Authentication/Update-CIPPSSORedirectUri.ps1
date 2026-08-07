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

    Additive only — it never removes a URI, so a domain bound out-of-band keeps working.

    .PARAMETER PassThru
    Emit a result object describing what happened. Off by default so warmup callers
    (Initialize-CIPPAuth) don't pick up stray pipeline output.
    #>
    [CmdletBinding()]
    param(
        [switch]$PassThru
    )

    $EmitResult = $PassThru.IsPresent

    # Local helper so every exit point returns the same shape (or nothing, without -PassThru)
    $Result = {
        param([string]$Status, [string[]]$RedirectUris, [string[]]$AddedUris, [string]$Message)
        if (-not $EmitResult) { return }
        [PSCustomObject]@{
            Status       = $Status
            RedirectUris = @($RedirectUris)
            AddedUris    = @($AddedUris)
            Message      = $Message
        }
    }

    $CurrentHost = $env:WEBSITE_HOSTNAME
    if (-not $CurrentHost) {
        Write-Information '[SSO-Redirect] WEBSITE_HOSTNAME not set, skipping redirect URI update'
        & $Result 'skipped' @() @() 'WEBSITE_HOSTNAME is not set — cannot determine this instance''s hostnames.'
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
        & $Result 'skipped' @() @() 'No SSO app registration is configured for this instance.'
        return
    }

    # Every bound hostname (custom domains + default) needs its own callback. When ARM can't be
    # reached this list is a best-effort fallback, not the full set of bound domains - the patch
    # below is still safe (it only adds), but we must not report "nothing missing" as an all-clear.
    $HostnameState = Get-CIPPSiteHostname -IncludeStatus
    $RequiredUris = @($HostnameState.RedirectUris)
    if (-not $HostnameState.Discovered) {
        Write-Information "[SSO-Redirect] Could not enumerate bound domains — working from known hostnames only: $($HostnameState.Error)"
    }

    try {
        $AppResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$SSOAppId')?`$select=id,web,signInAudience" -NoAuthCheck $true -AsApp $true
        $ExistingUris = @($AppResponse.web.redirectUris)

        # Determine which URIs are missing
        $MissingUris = @($RequiredUris | Where-Object { $_ -notin $ExistingUris })

        # Determine the expected signInAudience
        $ExpectedAudience = if ($SSOMultiTenant) { 'AzureADMultipleOrgs' } else { 'AzureADMyOrg' }
        $AudienceMismatch = $AppResponse.signInAudience -ne $ExpectedAudience

        if ($MissingUris.Count -eq 0 -and -not $AudienceMismatch) {
            Write-Information '[SSO-Redirect] All redirect URIs present and signInAudience correct'
            if ($HostnameState.Discovered) {
                & $Result 'nochange' $ExistingUris @() 'All sign-in URLs are already registered.'
            } else {
                & $Result 'partial' $ExistingUris @() "The sign-in URLs we could identify are already registered, but the list of custom domains bound to this instance could not be read, so some may be missing: $($HostnameState.Error)"
            }
            return
        }

        # Patch redirect URIs and signInAudience as separate requests. A tenant app-management
        # policy can reject an audience change (e.g. downgrading a multi-tenant app to
        # single-tenant fails with "SigninAudienceRestrictions with restricted mode can be
        # configured only on multi-tenants apps"). Sending them together would let that
        # rejection also drop the redirect URI additions, which are needed for sign-in.
        $UpdatedUris = [System.Collections.Generic.List[string]]::new()
        $ExistingUris | ForEach-Object { $UpdatedUris.Add($_) }
        if ($MissingUris.Count -gt 0) {
            $MissingUris | ForEach-Object { $UpdatedUris.Add($_) }
            $UriBody = @{ web = @{ redirectUris = $UpdatedUris } } | ConvertTo-Json -Depth 5
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $UriBody -type PATCH -NoAuthCheck $true -AsApp $true
            Write-Information "[SSO-Redirect] Added redirect URIs: $($MissingUris -join ', ')"
            Write-LogMessage -API 'SSO-Redirect' -message "Added redirect URIs: $($MissingUris -join ', ')" -sev Info
        }

        if ($AudienceMismatch) {
            Write-Information "[SSO-Redirect] Correcting signInAudience: $($AppResponse.signInAudience) -> $ExpectedAudience"
            try {
                $AudienceBody = @{ signInAudience = $ExpectedAudience } | ConvertTo-Json -Compress
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppResponse.id)" -body $AudienceBody -type PATCH -NoAuthCheck $true -AsApp $true
                Write-LogMessage -API 'SSO-Redirect' -message "Updated signInAudience to $ExpectedAudience (multiTenant=$SSOMultiTenant)" -sev Info
            } catch {
                # Non-fatal: a tenant app-management policy is blocking the audience change.
                # EasyAuth issuer validation already enforces the effective tenant scope, so the
                # app registration can stay as-is. Log at Info so warmup doesn't spam warnings.
                Write-Information "[SSO-Redirect] signInAudience change to $ExpectedAudience was rejected by tenant policy (leaving app reg as $($AppResponse.signInAudience)): $($_.Exception.Message)"
            }
        }

        $Summary = if ($MissingUris.Count -gt 0) { "Registered $($MissingUris.Count) new sign-in URL(s)." } else { 'Sign-in URLs were already up to date.' }
        if ($HostnameState.Discovered) {
            & $Result 'updated' $UpdatedUris $MissingUris $Summary
        } else {
            & $Result 'partial' $UpdatedUris $MissingUris "$Summary The full list of custom domains bound to this instance could not be read, so others may still be missing: $($HostnameState.Error)"
        }
        return
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'SSO-Redirect' -message "Failed to update SSO app registration: $_" -LogData $ErrorMessage -sev Warning
        & $Result 'error' @() @() $ErrorMessage.NormalizedError
        return
    }
}
