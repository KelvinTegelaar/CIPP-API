function New-CIPPMFAConnectorToken {
    <#
    .SYNOPSIS
        Returns an access token for the Azure MFA StrongAuthenticationService connector.

    .DESCRIPTION
        The connector token is minted from a client secret on the tenant's "Azure Multi-Factor Auth Client"
        service principal. Provisioning that secret is expensive (it may adjust the tenant's app management
        policy and add a credential), so a long-lived secret is cached per tenant - in Key Vault in
        production, in the DevSecrets table in local development - and reused. A cached secret is only
        reprovisioned when it is missing or the token exchange fails (e.g. it has expired). The provisioned
        secret is capped at 180 days; refresh happens automatically on the next call after it lapses.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The connector secret must be written to Key Vault as a SecureString and is encrypted at rest.')]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        $Headers,
        [switch]$ForceProvision
    )

    $MFAAppID = '981f26a1-7f43-403b-a875-f8b09b8cd720'
    $ConnectorResource = 'https://adnotifications.windowsazure.com/StrongAuthenticationService.svc/Connector'
    $TokenUri = "https://login.microsoftonline.com/$TenantFilter/oauth2/token"

    # Stable, Key-Vault-safe secret name keyed on the tenant GUID (domains contain dots, which KV rejects).
    $GuidPattern = '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
    $TenantId = if ($TenantFilter -match $GuidPattern) { $TenantFilter } else { (Get-Tenants -TenantFilter $TenantFilter).customerId }
    if (-not $TenantId) { $TenantId = $TenantFilter }
    $SecretName = "NPS-$TenantId"
    $IsDevMode = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'

    # --- dev-aware cached-secret storage -----------------------------------------------------------
    function Get-StoredSecret {
        if ($IsDevMode) {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'NPSSecret' and RowKey eq '$TenantId'"
            return $Row.SecretValue
        }
        # A missing secret is the normal first-call state for a tenant. The Key Vault helper throws on a
        # 404 rather than returning nothing, so treat not-found as "nothing cached yet" and let provisioning
        # create the secret. Any other retrieval failure is a real problem and propagates.
        try {
            return Get-CippKeyVaultSecret -Name $SecretName -AsPlainText -ErrorAction Stop
        } catch {
            if ($_.Exception.Message -match '404') { return $null }
            throw
        }
    }
    function Set-StoredSecret {
        param($Value)
        if ($IsDevMode) {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Entity = @{ PartitionKey = 'NPSSecret'; RowKey = [string]$TenantId; SecretValue = [string]$Value }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        } else {
            $null = Set-CippKeyVaultSecret -Name $SecretName -SecretValue (ConvertTo-SecureString -String $Value -AsPlainText -Force)
        }
    }

    # Keep retrying the token exchange while Microsoft finishes provisioning a freshly added secret.
    function Get-ConnectorToken {
        param($Secret, [int]$MaxAttempts = 1)
        $ClientBody = @{
            resource      = $ConnectorResource
            client_id     = $MFAAppID
            client_secret = $Secret
            grant_type    = 'client_credentials'
            scope         = 'openid'
        }
        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            try {
                return (Invoke-RestMethod -Method Post -Uri $TokenUri -Body $ClientBody -ErrorAction Stop).access_token
            } catch {
                $TokenError = $_
                $EntraError = try { ($TokenError.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop).error_description -replace '\s*Trace ID:[\s\S]*$' } catch { $null }
                $EnableHint = "Enable it with the 'Azure MFA push notification apps' baseline standard, or in Entra under Enterprise applications."
                switch -Regex ($EntraError) {
                    '^AADSTS7000112\b' { throw [System.UnauthorizedAccessException]"The Azure Multi-Factor Auth Client app ($MFAAppID) is disabled in this tenant. $EnableHint" }
                    '^AADSTS500014\b' { throw [System.UnauthorizedAccessException]"The Azure Multi-Factor Auth Connector app (1f5530b3-261a-47a9-b357-ded261e17918) is disabled in this tenant. $EnableHint" }
                }
                if ($Attempt -ge $MaxAttempts) {
                    throw "Failed to get a token for the Azure Multi-Factor Auth Client app: $($EntraError ?? $TokenError.Exception.Message)"
                }
                Start-Sleep 1
            }
        }
    }

    # 1. Reuse the cached secret when present (single token attempt - it is already active).
    if (-not $ForceProvision) {
        $CachedSecret = Get-StoredSecret
        if ($CachedSecret) {
            try {
                return [pscustomobject]@{ AccessToken = (Get-ConnectorToken -Secret $CachedSecret) }
            } catch [System.UnauthorizedAccessException] {
                throw
            } catch {
                # Cached secret is expired or revoked - fall through and reprovision.
                Write-Information "Cached MFA connector secret for $TenantId failed token exchange; reprovisioning."
            }
        }
    }

    # 2. Provision a fresh long-lived secret on the MFA client service principal.
    $SP = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$MFAAppID'&`$select=id,passwordCredentials" -tenantid $TenantFilter -AsApp $true | Select-Object -First 1
    $SPID = $SP.id
    if (!$SPID) {
        $SPBody = [pscustomobject]@{ appId = $MFAAppID } | ConvertTo-Json -Depth 5
        $SPID = (New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $TenantFilter -type POST -body $SPBody -AsApp $true).id
    }

    try {
        $PolicyUpdate = Update-AppManagementPolicy -TenantFilter $TenantFilter -ApplicationId $MFAAppID -ServicePrincipal -PolicyName 'CIPP MFA Connector Exemption Policy' -ExemptPasswordLifetime -headers $Headers
        if ($PolicyUpdate.PolicyAction) {
            Write-LogMessage -headers $Headers -API 'MFAConnector' -tenant $TenantFilter -message "App management policy for the Azure Multi-Factor Auth Client: $($PolicyUpdate.PolicyAction)" -sev Info
        }
    } catch {
        Write-LogMessage -headers $Headers -API 'MFAConnector' -tenant $TenantFilter -message "Failed to update app management policy for the Azure Multi-Factor Auth Client: $($_.Exception.Message)" -sev Warn
    }

    $SecretStart = (Get-Date).AddMinutes(-5)
    $SecretLifetime = [timespan]::FromDays(180)
    $NewSecret = $null
    $AddSecretError = $null
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        $PassReqBody = @{
            'passwordCredential' = @{
                'displayName'   = 'CIPP MFA Connector'
                'endDateTime'   = $SecretStart + $SecretLifetime
                'startDateTime' = $SecretStart
            }
        } | ConvertTo-Json -Depth 5
        try {
            $NewSecret = (New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPID/addPassword" -tenantid $TenantFilter -type POST -body $PassReqBody -AsApp $true).secretText
            break
        } catch {
            $AddSecretError = $_.Exception.Message
            $TenantMaxLifetime = ($PolicyUpdate.DefaultPolicy.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordLifetime' -and $_.state -eq 'enabled' } | Select-Object -First 1).maxLifetime
            if ($AddSecretError -match 'lifetime exceeds' -and $TenantMaxLifetime) {
                $SecretLifetime = [System.Xml.XmlConvert]::ToTimeSpan($TenantMaxLifetime).Add([timespan]::FromHours(-1))
                continue
            }
            $ExpiredSecrets = @($SP.passwordCredentials).Where({ $_.displayName -in @('CIPP MFA Connector', 'MFA Temporary Password') -and [datetime]$_.endDateTime -lt (Get-Date) })
            $SP = $null
            foreach ($ExpiredSecret in $ExpiredSecrets) {
                try {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPID/removePassword" -tenantid $TenantFilter -type POST -body (@{ keyId = $ExpiredSecret.keyId } | ConvertTo-Json) -AsApp $true
                } catch {
                    Write-Information "Failed to remove expired MFA connector secret $($ExpiredSecret.keyId) for $($TenantId): $($_.Exception.Message)"
                }
            }
            if ($ExpiredSecrets.Count -gt 0) {
                Write-LogMessage -headers $Headers -API 'MFAConnector' -tenant $TenantFilter -message "Removed $($ExpiredSecrets.Count) expired MFA connector secret(s) from the Azure Multi-Factor Auth Client after a failed secret add" -sev Info
                continue
            }
            if ($Attempt -lt 5) { Start-Sleep -Seconds 4 }
        }
    }
    if (-not $NewSecret) {
        throw "Failed to add a credential to the MFA service principal. The tenant's app management policy may be blocking credential creation for this app. Error: $AddSecretError"
    }

    $AccessToken = Get-ConnectorToken -Secret $NewSecret -MaxAttempts 20
    Set-StoredSecret -Value $NewSecret

    return [pscustomobject]@{ AccessToken = $AccessToken }
}
