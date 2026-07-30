function Update-CIPPSSOPreconsent {
    <#
    .SYNOPSIS
    Grants tenant-wide admin consent to the CIPP-SSO app registration so users are not
    prompted to consent when they sign in.

    .DESCRIPTION
    Reads the stored SSO AppId from Key Vault (or the DevSecrets table in dev mode) and
    ensures an AllPrincipals oauth2PermissionGrant exists for it against Microsoft Graph
    covering the delegated scopes New-CIPPSSOApp requests (openid, profile, email).

    Runs from warmup rather than at app-creation time: the service principal is not always
    queryable immediately after the app registration is created, so a create-time grant is
    racy. Retrying every warmup makes it self-healing at no cost once it has succeeded.

    Best-effort by design. A tenant whose SAM consent predates Directory.ReadWrite.All will
    get a 403 here, which is recorded as Preconsented=false and otherwise ignored — sign-in
    still works, users just see the consent prompt they see today.

    Only covers the home tenant. A multi-tenant SSO app still prompts users from other
    tenants, because the grant can only be written where CIPP holds credentials.
    #>
    [CmdletBinding()]
    param()

    $GraphAppId = '00000003-0000-0000-c000-000000000000'
    # Keep in sync with the delegated permissions New-CIPPSSOApp requests.
    $RequiredScopes = @('openid', 'profile', 'email')

    $MigrationTable = Get-CIPPTable -TableName 'SSOMigration'
    $Existing = $null
    try {
        $Existing = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" -ErrorAction SilentlyContinue
    } catch { }

    # Merge onto the existing row — Add-CIPPAzDataTableEntity -Force replaces, and this row
    # carries the setup state the SSO settings page reads.
    $SaveRow = {
        param([hashtable]$Updates)
        $Row = @{
            PartitionKey = 'SSO'
            RowKey       = 'MigrationConfig'
        }
        if ($Existing) {
            foreach ($Prop in $Existing.PSObject.Properties) {
                if ($Prop.Name -notin @('PartitionKey', 'RowKey', 'Timestamp', 'ETag', 'odata.etag')) {
                    $Row[$Prop.Name] = $Prop.Value
                }
            }
        }
        foreach ($Key in $Updates.Keys) { $Row[$Key] = $Updates[$Key] }
        try {
            Add-CIPPAzDataTableEntity @MigrationTable -Entity $Row -Force | Out-Null
        } catch {
            Write-Information "[SSO-Preconsent] Failed to record status: $($_.Exception.Message)"
        }
    }

    # Resolve the stored SSO AppId
    $SSOAppId = $null
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        try {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'" -ErrorAction SilentlyContinue
            $SSOAppId = $Secret.SSOAppId
        } catch { }
    } else {
        $VaultName = Get-CippKeyVaultName
        if ($VaultName) {
            try {
                $SSOAppId = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'SSOAppId' -AsPlainText -ErrorAction Stop
            } catch { }
        }
    }

    if (-not $SSOAppId) {
        Write-Information '[SSO-Preconsent] No SSO AppId found, skipping pre-consent'
        return
    }

    # Fast path: already granted for this app. Tracked against the AppId so recreating the
    # SSO app re-runs the grant instead of trusting a flag left over from the old one.
    if ($Existing.Preconsented -eq 'true' -and $Existing.PreconsentedAppId -eq $SSOAppId) {
        Write-Information "[SSO-Preconsent] Already granted for $SSOAppId — skipping"
        return
    }

    # Looked up separately from the grant work below: a service principal that isn't
    # queryable yet is a propagation delay, not a refusal, and shouldn't be recorded as
    # Preconsented=false. Graph 404s throw here rather than returning null.
    $SsoSp = $null
    try {
        $SsoSp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$SSOAppId')?`$select=id" -NoAuthCheck $true -AsApp $true
    } catch {
        Write-Information "[SSO-Preconsent] Service principal lookup for $SSOAppId failed — will retry next warmup: $($_.Exception.Message)"
        return
    }
    if (-not $SsoSp.id) {
        Write-Information "[SSO-Preconsent] Service principal for $SSOAppId not found yet — will retry next warmup"
        return
    }

    try {
        $GraphSp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$GraphAppId')?`$select=id" -NoAuthCheck $true -AsApp $true
        if (-not $GraphSp.id) {
            Write-Information '[SSO-Preconsent] Microsoft Graph service principal not found — skipping'
            return
        }

        $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($SsoSp.id)/oauth2PermissionGrants" -NoAuthCheck $true -AsApp $true)
        $TenantGrant = $Grants | Where-Object { $_.resourceId -eq $GraphSp.id -and $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1

        if ($TenantGrant) {
            $CurrentScopes = @($TenantGrant.scope -split ' ' | Where-Object { $_ })
            $MissingScopes = @($RequiredScopes | Where-Object { $_ -notin $CurrentScopes })

            if ($MissingScopes.Count -eq 0) {
                Write-Information "[SSO-Preconsent] Admin consent already in place for $SSOAppId"
                & $SaveRow @{
                    Preconsented      = 'true'
                    PreconsentedAppId = $SSOAppId
                    PreconsentError   = ''
                }
                return
            }

            $MergedScopes = (@($CurrentScopes + $MissingScopes) | Sort-Object -Unique) -join ' '
            $PatchBody = @{ scope = $MergedScopes } | ConvertTo-Json -Compress
            New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($TenantGrant.id)" -body $PatchBody -type PATCH -NoAuthCheck $true -AsApp $true
            Write-Information "[SSO-Preconsent] Added missing scopes to existing grant: $($MissingScopes -join ', ')"
        } else {
            $CreateBody = @{
                clientId    = $SsoSp.id
                consentType = 'AllPrincipals'
                resourceId  = $GraphSp.id
                scope       = $RequiredScopes -join ' '
            } | ConvertTo-Json -Compress
            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -body $CreateBody -type POST -NoAuthCheck $true -AsApp $true
            Write-Information "[SSO-Preconsent] Granted admin consent for $SSOAppId ($($RequiredScopes -join ', '))"
        }

        $StatusUpdates = @{
            Preconsented      = 'true'
            PreconsentedAppId = $SSOAppId
            PreconsentedAt    = (Get-Date).ToUniversalTime().ToString('o')
            PreconsentError   = ''
        }
        # A row created here must carry a Status, or the SSO settings page reads it back as
        # "not provisioned" and offers to create an app that already exists.
        if (-not $Existing -or -not $Existing.Status) {
            $StatusUpdates['AppId'] = $SSOAppId
            $StatusUpdates['Status'] = if ($env:WEBSITE_AUTH_ENABLED -eq 'True') { 'complete' } else { 'secrets_stored' }
        }
        & $SaveRow $StatusUpdates

        Write-LogMessage -API 'SSO-Preconsent' -message "Admin consent granted for CIPP-SSO app $SSOAppId" -sev Info
    } catch {
        # Non-fatal: sign-in still works, users just get the consent prompt. Most likely cause
        # is a SAM consent predating Directory.ReadWrite.All, which no retry will fix.
        $ErrorMessage = $_.Exception.Message
        Write-Information "[SSO-Preconsent] Pre-consent failed for $SSOAppId (non-fatal): $ErrorMessage"
        & $SaveRow @{
            Preconsented      = 'false'
            PreconsentedAppId = $SSOAppId
            PreconsentError   = $ErrorMessage
        }
        Write-LogMessage -API 'SSO-Preconsent' -message "Could not pre-consent CIPP-SSO app $SSOAppId — users will see a consent prompt on sign-in: $ErrorMessage" -LogData (Get-CippException -Exception $_) -sev Warning
    }
}
