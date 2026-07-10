function Update-CIPPSAMCertificate {
    <#
    .SYNOPSIS
    Creates or renews the SAM app certificate

    .DESCRIPTION
    Checks the stored SAM certificate and renews it when missing (first-run bootstrap),
    within the renewal threshold of expiry, or when the stored certificate is not registered
    on the SAM app (drift from a previously failed run). Renewal generates a new self-signed
    certificate, registers it on the app registration via a full keyCredentials PATCH
    (addKey requires a proof-of-possession token signed by an existing key, which is
    impossible at bootstrap), then stores the PFX via Set-CIPPSAMCertificate. Still-valid
    existing key credentials are kept during rotation so in-flight assertions keep working;
    expired ones are pruned in the same PATCH. If storage fails, the new credential is
    rolled back off the app registration so renewal is retried on the next run.

    .PARAMETER RenewalThresholdDays
    Renew when the stored certificate expires within this many days. Defaults to 30.

    .PARAMETER Force
    Renew regardless of the stored certificate's expiry.

    .PARAMETER ApplicationId
    The app registration (client) id to manage the certificate for. Defaults to the SAM app.

    .PARAMETER Headers
    Optional pre-built authorization headers for the Graph calls (e.g. the delegated token
    during the setup wizard, before the app's own credentials are usable).

    .EXAMPLE
    Update-CIPPSAMCertificate

    .EXAMPLE
    Update-CIPPSAMCertificate -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [int]$RenewalThresholdDays = 30,

        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [string]$ApplicationId,

        [Parameter(Mandatory = $false)]
        $Headers
    )

    $AppId = if ($ApplicationId) { $ApplicationId } else { $env:ApplicationID }
    $AppRegistration = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')?`$select=id,keyCredentials" -NoAuthCheck $true -AsApp $true -Headers $Headers -ErrorAction Stop

    $Stored = $null
    try {
        $Stored = Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop
    } catch {
        Write-Warning "Could not retrieve stored SAM certificate: $($_.Exception.Message)"
    }

    $RenewalReason = if ($Force) {
        'Forced renewal requested'
    } elseif ($null -eq $Stored) {
        'No stored certificate found, creating initial certificate'
    } elseif ($Stored.NotAfter -lt (Get-Date).AddDays($RenewalThresholdDays).ToUniversalTime()) {
        "Stored certificate expires $($Stored.NotAfter), within the $RenewalThresholdDays day renewal threshold"
    } else {
        # Drift check: the stored certificate should be registered on the app. If it is not,
        # a previous run failed between storage and Graph (or its rollback failed) - self-heal.
        # Graph returns customKeyIdentifier as the hex thumbprint string, but tolerate the
        # base64-encoded thumbprint bytes form as well.
        $Identifiers = @($AppRegistration.keyCredentials.customKeyIdentifier)
        if ($Identifiers -notcontains $Stored.Thumbprint -and $Identifiers -notcontains [Convert]::ToBase64String([Convert]::FromHexString($Stored.Thumbprint))) {
            'Stored certificate is not registered on the app registration, re-registering'
        } else {
            $null
        }
    }

    if (-not $RenewalReason) {
        Write-Information "SAM certificate is valid until $($Stored.NotAfter) and registered on the app. No renewal needed."
        return [PSCustomObject]@{
            Renewed    = $false
            Thumbprint = $Stored.Thumbprint
            NotAfter   = $Stored.NotAfter
        }
    }

    if (-not $PSCmdlet.ShouldProcess($AppId, "Renew SAM certificate: $RenewalReason")) {
        return
    }

    Write-Information "Renewing SAM certificate for $AppId. Reason: $RenewalReason"

    # Ensure the CIPP exemption policy covers key credential restrictions (asymmetricKeyLifetime /
    # trustedCertificateAuthority would otherwise block registering a 1 year self-signed certificate)
    try {
        $AppPolicyStatus = Update-AppManagementPolicy -ApplicationId $AppId -Headers $Headers
        if ($AppPolicyStatus.PolicyAction) { Write-Information $AppPolicyStatus.PolicyAction }
    } catch {
        Write-Warning "Error updating app management policy $($_.Exception.Message)."
    }

    $NewCert = New-CIPPSAMCertificate

    # Keep still-valid credentials (rotation overlap) and prune expired ones in the same PATCH.
    # Existing credentials are sent back with their keyId and null key material, which Graph
    # preserves; only the appended entry carries new key material.
    $Now = (Get-Date).ToUniversalTime()
    $KeyCredentials = [System.Collections.Generic.List[object]]::new()
    foreach ($Credential in $AppRegistration.keyCredentials) {
        if ($Credential.endDateTime -ge $Now) {
            $KeyCredentials.Add($Credential)
        } else {
            Write-Information "Pruning expired key credential $($Credential.keyId) (expired $($Credential.endDateTime))"
        }
    }
    # Record which instance issued the certificate: machine name for local dev, site name in Azure
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $InstanceName = [System.Environment]::MachineName
    } else {
        $InstanceName = $env:WEBSITE_SITE_NAME
    }
    $KeyCredentials.Add(@{
            type        = 'AsymmetricX509Cert'
            usage       = 'Verify'
            key         = $NewCert.PublicKeyBase64
            displayName = "CIPP-SAM Certificate ($InstanceName)"
        })

    $PatchBody = @{ keyCredentials = $KeyCredentials } | ConvertTo-Json -Compress -Depth 10
    New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)" -Body $PatchBody -NoAuthCheck $true -AsApp $true -Headers $Headers -ErrorAction Stop
    Write-Information "Registered new SAM certificate $($NewCert.Thumbprint) on application $AppId"

    try {
        $StoreResult = Set-CIPPSAMCertificate -PfxBase64 $NewCert.PfxBase64 -ErrorAction Stop
    } catch {
        # The new certificate is registered on the app but not retrievable where CIPP reads it,
        # and as the newest credential it would suppress renewal on the next run. Roll it back
        # off the app registration so state stays consistent and renewal is retried.
        Write-LogMessage -API 'SAMCertificate' -message "Failed to store new SAM certificate for $AppId. Rolling back the registered key credential, see Log Data for details." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        try {
            $RollbackCredentials = $KeyCredentials | Where-Object { $_.key -ne $NewCert.PublicKeyBase64 }
            $RollbackBody = @{ keyCredentials = @($RollbackCredentials) } | ConvertTo-Json -Compress -Depth 10
            New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)" -Body $RollbackBody -NoAuthCheck $true -AsApp $true -Headers $Headers -ErrorAction Stop
            Write-Information "Rolled back unstored SAM certificate $($NewCert.Thumbprint) from application $AppId"
        } catch {
            # Rollback failed - the drift check on the next run will force a fresh renewal
            Write-LogMessage -API 'SAMCertificate' -message "Failed to roll back unstored SAM certificate $($NewCert.Thumbprint) for $AppId, see Log Data for details. Renewal will retry on the next run." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        }
        throw
    }

    Write-LogMessage -API 'SAMCertificate' -message "SAM certificate renewed for $AppId. Thumbprint: $($NewCert.Thumbprint), expires: $($NewCert.NotAfter), storage mode: $($StoreResult.StorageMode). Reason: $RenewalReason" -sev 'Info'

    return [PSCustomObject]@{
        Renewed     = $true
        Thumbprint  = $NewCert.Thumbprint
        NotAfter    = $NewCert.NotAfter
        StorageMode = $StoreResult.StorageMode
    }
}
