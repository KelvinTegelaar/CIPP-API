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
                if ($Attempt -ge $MaxAttempts) { throw }
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
            } catch {
                # Cached secret is expired or revoked - fall through and reprovision.
                Write-Information "Cached MFA connector secret for $TenantId failed token exchange; reprovisioning."
            }
        }
    }

    # 2. Provision a fresh long-lived secret on the MFA client service principal.
    $SPResult = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$top=999&`$select=id,appId" -tenantid $TenantFilter -AsApp $true
    $SPID = ($SPResult | Where-Object { $_.appId -eq $MFAAppID }).id
    if (!$SPID) {
        $SPBody = [pscustomobject]@{ appId = $MFAAppID } | ConvertTo-Json -Depth 5
        $SPID = (New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -tenantid $TenantFilter -type POST -body $SPBody -AsApp $true).id
    }

    try {
        $PolicyUpdate = Update-AppManagementPolicy -TenantFilter $TenantFilter -ApplicationId $MFAAppID -ServicePrincipal
        Write-Information $PolicyUpdate.PolicyAction
    } catch {
        Write-Information "Failed to update app management policy: $($_.Exception.Message)"
    }

    $PassReqBody = @{
        'passwordCredential' = @{
            'displayName'   = 'CIPP MFA Connector'
            'endDateTime'   = $((Get-Date).AddDays(180))
            'startDateTime' = $((Get-Date).AddMinutes(-5))
        }
    } | ConvertTo-Json -Depth 5

    $NewSecret = $null
    $AddSecretError = $null
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        try {
            $NewSecret = (New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPID/addPassword" -tenantid $TenantFilter -type POST -body $PassReqBody -AsApp $true).secretText
            break
        } catch {
            $AddSecretError = $_.Exception.Message
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
