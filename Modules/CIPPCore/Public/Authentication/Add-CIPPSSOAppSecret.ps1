function Add-CIPPSSOAppSecret {
    <#
    .SYNOPSIS
        Creates a client secret on the CIPP-SSO app registration with retry.
    .DESCRIPTION
        Adds a new password credential to the given app object via Graph. Before adding the
        secret it ensures the app is exempt from the tenant default app-management policy (so a
        'passwordAddition' restriction can't block the secret) via Update-AppManagementPolicy,
        and honours any 'passwordLifetime' restriction when building the credential body.
        Retries up to MaxRetries times with backoff because Entra propagation can take a few
        seconds after the app is freshly created or its app-management-policy exemption is set:
        replication misses back off 3s, and credential-policy blocks back off min(30, 5*attempt)s
        while the exemption propagates. Throws on final failure so callers can persist
        Status=error + LastError.
    .PARAMETER ObjectId
        Graph object ID of the application (NOT the appId/clientId).
    .PARAMETER AppId
        AppId/clientId of the application, used to target the app-management-policy exemption.
        Resolved from ObjectId when not supplied.
    .PARAMETER DisplayName
        Display name to set on the password credential. Defaults to 'CIPP-SSO-Secret'.
    .PARAMETER MaxRetries
        Number of secret-creation attempts before giving up. Defaults to 6.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [string]$AppId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName = 'CIPP-SSO-Secret',

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 6
    )

    # Update-AppManagementPolicy targets the app by appId/clientId; resolve it from the object id when not supplied.
    if (-not $AppId) {
        try {
            $SSOApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications/$ObjectId`?`$select=id,appId" -NoAuthCheck $true -AsApp $true
            $AppId = $SSOApp.appId
        } catch {
            Write-Warning "[SSO-Secret] Failed to resolve appId for objectId $ObjectId : $($_.Exception.Message)"
        }
    }

    # Ensure the app is exempt from any credential-addition restriction before adding the secret.
    if ($AppId) {
        try {
            $PolicyUpdate = Update-AppManagementPolicy -ApplicationId $AppId
            Write-Information "[SSO-Secret] App management policy: $($PolicyUpdate.PolicyAction)"
        } catch {
            Write-Information "[SSO-Secret] Failed to update app management policy: $($_.Exception.Message)"
        }
    }

    # Honour the tenant password-lifetime restriction (if enforced) when building the credential body.
    $AppManagementPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy' -AsApp $true -NoAuthCheck $true
    $PasswordExpirationPolicy = $AppManagementPolicy.applicationRestrictions.passwordcredentials |
        Where-Object { $_.restrictionType -eq 'passwordLifetime' }
    if (-not ($PasswordExpirationPolicy.state -eq 'disabled' -or $null -eq $PasswordExpirationPolicy.state)) {
        $TimeToExpiration = [System.Xml.XmlConvert]::ToTimeSpan($PasswordExpirationPolicy.maxLifetime)
        $ExpirationDate = (Get-Date).AddDays($TimeToExpiration.Days).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $PasswordBody = "{`"passwordCredential`":{`"displayName`":`"$DisplayName`",`"endDateTime`":`"$ExpirationDate`"}}"
    } else {
        $PasswordBody = "{`"passwordCredential`":{`"displayName`":`"$DisplayName`"}}"
    }

    $SecretText = $null
    $LastException = $null
    for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
        try {
            $PasswordResult = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$ObjectId/addPassword" -AsApp $true -NoAuthCheck $true -type POST -body $PasswordBody -maxRetries 3
            $SecretText = $PasswordResult.secretText
            Write-Information "[SSO-Secret] Client secret created on objectId $ObjectId"
            break
        } catch {
            $LastException = $_
            $ExceptionMessage = $_.Exception.Message
            $IsNotReplicatedYet = $ExceptionMessage -match "Resource '.*' does not exist or one of its queried reference-property objects are not present"
            $IsCredentialPolicyBlocked = $ExceptionMessage -match 'Credential type not allowed as per assigned policy'
            Write-Warning "[SSO-Secret] Secret creation attempt $Attempt/$MaxRetries failed: $ExceptionMessage"

            if ($IsNotReplicatedYet -and $Attempt -lt $MaxRetries) {
                $DelaySeconds = 3
                Write-Information "[SSO-Secret] Application object not yet replicated for addPassword (attempt $Attempt of $MaxRetries). Retrying in $DelaySeconds second(s)."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }

            if ($IsCredentialPolicyBlocked -and $Attempt -lt $MaxRetries) {
                $DelaySeconds = [Math]::Min(30, 5 * $Attempt)
                Write-Information "[SSO-Secret] Credential policy still blocks addPassword (attempt $Attempt of $MaxRetries). Waiting for policy propagation and retrying in $DelaySeconds second(s)."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }

            throw
        }
    }

    if (-not $SecretText) {
        $InnerMessage = if ($LastException) { $LastException.Exception.Message } else { 'unknown error' }
        throw "Failed to create client secret for CIPP-SSO after $MaxRetries attempts: $InnerMessage"
    }

    return $SecretText
}
