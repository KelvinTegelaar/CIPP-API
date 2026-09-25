function Update-CIPPSAMCertificate {
    <#
    .SYNOPSIS
    Creates, renews, or reconciles the SAM app certificate

    .DESCRIPTION
    Loads Key Vault SAMCertificate current/previous versions as the Entra keep-set.
    On every run, removes proven CIPP debris (older KV thumbprints or CIPP-SAM displayName
    orphans) while preserving unknown credentials. Mints only when missing, near expiry,
    or -Force. Drift re-registers the same stored public key without minting. Renewal
    keeps at most the previous current plus the new cert, then stores the PFX under the
    same KV name. Store failure rolls back only the newly added credential.

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

    $Versions = $null
    try {
        $Versions = Get-CIPPSAMCertificateVersions -ErrorAction Stop
    } catch {
        Write-Warning "Could not retrieve SAM certificate versions: $($_.Exception.Message). Falling back to latest stored certificate."
        try {
            $Fallback = Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop
            if ($Fallback) {
                $PublicKeyBase64 = [Convert]::ToBase64String(
                    $Fallback.Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                )
                $CurrentInfo = [PSCustomObject]@{
                    Certificate     = $Fallback.Certificate
                    Thumbprint      = $Fallback.Thumbprint
                    NotBefore       = $Fallback.NotBefore
                    NotAfter        = $Fallback.NotAfter
                    PfxBase64       = $null
                    PublicKeyBase64 = $PublicKeyBase64
                }
                $Versions = [PSCustomObject]@{
                    Current               = $CurrentInfo
                    Previous              = $null
                    HistoricalThumbprints = [string[]]@()
                    AllKnownThumbprints   = @($Fallback.Thumbprint)
                }
                Write-Information "Using latest SAM certificate $($Fallback.Thumbprint) after versions load failure; historical prune skipped this run."
            } else {
                $Versions = [PSCustomObject]@{
                    Current               = $null
                    Previous              = $null
                    HistoricalThumbprints = [string[]]@()
                    AllKnownThumbprints   = [string[]]@()
                }
            }
        } catch {
            # Fail closed: a transient KV error must not be treated as "no cert" and force a mint.
            Write-LogMessage -API 'SAMCertificate' -message "Could not load SAM certificate versions or the latest stored certificate. Skipping renewal to avoid rotating a still-valid cert. See Log Data for details." -sev 'Warning' -LogData (Get-CippException -Exception $_)
            throw "SAM certificate storage is temporarily unavailable; renewal skipped to avoid forced rotation. $($_.Exception.Message)"
        }
    }

    $Current = $Versions.Current
    $Previous = $Versions.Previous
    $HistoricalThumbprints = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Tp in @($Versions.HistoricalThumbprints)) {
        if ($Tp) { [void]$HistoricalThumbprints.Add($Tp) }
    }

    $KnownForResolve = [System.Collections.Generic.List[string]]::new()
    foreach ($Tp in @($Versions.AllKnownThumbprints)) {
        if ($Tp) { $KnownForResolve.Add($Tp) }
    }

    $NeedMint = $false
    $MintReason = $null
    if ($Force) {
        $NeedMint = $true
        $MintReason = 'Forced renewal requested'
    } elseif ($null -eq $Current) {
        $NeedMint = $true
        $MintReason = 'No stored certificate found, creating initial certificate'
    } elseif ($Current.NotAfter -lt (Get-Date).AddDays($RenewalThresholdDays).ToUniversalTime()) {
        $NeedMint = $true
        $MintReason = "Stored certificate expires $($Current.NotAfter), within the $RenewalThresholdDays day renewal threshold"
    }

    # Keep-set on Entra: current+previous normally; during mint only pre-write current (becomes previous) + new.
    $KeepThumbprints = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($NeedMint) {
        if ($Current.Thumbprint) { [void]$KeepThumbprints.Add($Current.Thumbprint) }
    } else {
        if ($Current.Thumbprint) { [void]$KeepThumbprints.Add($Current.Thumbprint) }
        if ($Previous.Thumbprint) { [void]$KeepThumbprints.Add($Previous.Thumbprint) }
    }

    $Classification = Get-CIPPSAMCredentialClassification -Credentials $AppRegistration.keyCredentials -KeepThumbprints $KeepThumbprints -HistoricalThumbprints $HistoricalThumbprints -KnownThumbprints $KnownForResolve
    $Drift = $false
    if ($Current -and -not $NeedMint) {
        $Drift = -not (Test-CIPPSAMAppHasThumbprint -Credentials $AppRegistration.keyCredentials -Thumbprint $Current.Thumbprint)
        if ($Drift) {
            Write-Information "Stored SAM certificate $($Current.Thumbprint) is not registered on the app; will re-register"
        }
    }

    $NeedReconcile = $Drift -or ($Classification.RemovedCount -gt 0)
    if (-not $NeedMint -and -not $NeedReconcile) {
        Write-Information "SAM certificate is valid until $($Current.NotAfter) and registered on the app. No renewal or reconcile needed."
        return [PSCustomObject]@{
            Renewed     = $false
            Reconciled  = $false
            Thumbprint  = $Current.Thumbprint
            NotAfter    = $Current.NotAfter
            RemovedCount = 0
        }
    }

    $ActionDescription = if ($NeedMint) { "Renew SAM certificate: $MintReason" } elseif ($Drift) { 'Re-register stored SAM certificate (drift)' } else { "Reconcile SAM keyCredentials (remove $($Classification.RemovedCount) CIPP debris)" }
    if (-not $PSCmdlet.ShouldProcess($AppId, $ActionDescription)) {
        return
    }

    Write-Information "$ActionDescription for $AppId"

    try {
        $AppPolicyStatus = Update-AppManagementPolicy -ApplicationId $AppId -Headers $Headers
        if ($AppPolicyStatus.PolicyAction) { Write-Information $AppPolicyStatus.PolicyAction }
    } catch {
        Write-Warning "Error updating app management policy $($_.Exception.Message)."
    }

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $InstanceName = [System.Environment]::MachineName
    } else {
        $InstanceName = $env:WEBSITE_SITE_NAME
    }

    $KeyCredentials = [System.Collections.Generic.List[object]]::new()
    foreach ($Credential in $Classification.KeepCredentials) {
        $KeyCredentials.Add($Credential)
    }

    $NewCert = $null
    if ($NeedMint) {
        $NewCert = New-CIPPSAMCertificate
        if ($NewCert.Thumbprint) { $KnownForResolve.Add($NewCert.Thumbprint) }
        $KeyCredentials.Add(@{
                type        = 'AsymmetricX509Cert'
                usage       = 'Verify'
                key         = $NewCert.PublicKeyBase64
                displayName = "CIPP-SAM Certificate ($InstanceName)"
            })
    } elseif ($Drift -and $Current.PublicKeyBase64) {
        $KeyCredentials.Add(@{
                type        = 'AsymmetricX509Cert'
                usage       = 'Verify'
                key         = $Current.PublicKeyBase64
                displayName = "CIPP-SAM Certificate ($InstanceName)"
            })
    }

    $PatchBody = @{ keyCredentials = @($KeyCredentials) } | ConvertTo-Json -Compress -Depth 10
    New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)" -Body $PatchBody -NoAuthCheck $true -AsApp $true -Headers $Headers -ErrorAction Stop

    if ($NeedMint) {
        Write-Information "Registered new SAM certificate $($NewCert.Thumbprint) on application $AppId (removed $($Classification.RemovedCount) CIPP debris)"
        try {
            $StoreResult = Set-CIPPSAMCertificate -PfxBase64 $NewCert.PfxBase64 -ErrorAction Stop
        } catch {
            Write-LogMessage -API 'SAMCertificate' -message "Failed to store new SAM certificate for $AppId. Rolling back the registered key credential, see Log Data for details." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
            try {
                $RollbackCredentials = @($KeyCredentials | Where-Object { $_.key -ne $NewCert.PublicKeyBase64 })
                $RollbackBody = @{ keyCredentials = @($RollbackCredentials) } | ConvertTo-Json -Compress -Depth 10
                New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)" -Body $RollbackBody -NoAuthCheck $true -AsApp $true -Headers $Headers -ErrorAction Stop
                Write-Information "Rolled back unstored SAM certificate $($NewCert.Thumbprint) from application $AppId"
            } catch {
                Write-LogMessage -API 'SAMCertificate' -message "Failed to roll back unstored SAM certificate $($NewCert.Thumbprint) for $AppId, see Log Data for details. Renewal will retry on the next run." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
            }
            throw
        }

        Write-LogMessage -API 'SAMCertificate' -message "SAM certificate renewed for $AppId. Thumbprint: $($NewCert.Thumbprint), expires: $($NewCert.NotAfter), storage mode: $($StoreResult.StorageMode). Reason: $MintReason. Removed $($Classification.RemovedCount) CIPP debris." -sev 'Info'

        return [PSCustomObject]@{
            Renewed      = $true
            Reconciled   = ($Classification.RemovedCount -gt 0)
            Thumbprint   = $NewCert.Thumbprint
            NotAfter     = $NewCert.NotAfter
            StorageMode  = $StoreResult.StorageMode
            RemovedCount = $Classification.RemovedCount
        }
    }

    $ResultThumbprint = $Current.Thumbprint
    $ResultNotAfter = $Current.NotAfter
    Write-LogMessage -API 'SAMCertificate' -message "SAM certificate reconciled for $AppId. Thumbprint: $ResultThumbprint, drift=$Drift, removed $($Classification.RemovedCount) CIPP debris." -sev 'Info'

    return [PSCustomObject]@{
        Renewed      = $false
        Reconciled   = $true
        Thumbprint   = $ResultThumbprint
        NotAfter     = $ResultNotAfter
        RemovedCount = $Classification.RemovedCount
        Drift        = $Drift
    }
}

function Get-CIPPSAMCredentialClassification {
    <#
    .SYNOPSIS
    Classifies app keyCredentials into keep vs remove for SAM cert reconcile
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $Credentials,
        [System.Collections.Generic.HashSet[string]]$KeepThumbprints,
        [System.Collections.Generic.HashSet[string]]$HistoricalThumbprints,
        [System.Collections.Generic.List[string]]$KnownThumbprints
    )

    $KeepCredentials = [System.Collections.Generic.List[object]]::new()
    $RemovedCount = 0

    foreach ($Credential in @($Credentials)) {
        $Thumbprint = Resolve-CIPPSAMCredentialThumbprint -Credential $Credential -KnownThumbprints $KnownThumbprints

        if ($Thumbprint -and $KeepThumbprints.Contains($Thumbprint)) {
            $KeepCredentials.Add($Credential)
            continue
        }

        if ($null -eq $Thumbprint) {
            # Cannot prove identity — leave alone
            $KeepCredentials.Add($Credential)
            continue
        }

        $IsCippDisplayName = $Credential.displayName -like 'CIPP-SAM Certificate*'
        $InHistorical = $HistoricalThumbprints.Contains($Thumbprint)
        if ($InHistorical -or $IsCippDisplayName) {
            $RemovedCount++
            Write-Information "Pruning CIPP key credential $($Credential.keyId) thumbprint=$Thumbprint displayName=$($Credential.displayName)"
            continue
        }

        $KeepCredentials.Add($Credential)
    }

    return [PSCustomObject]@{
        KeepCredentials = $KeepCredentials
        RemovedCount    = $RemovedCount
    }
}

function Resolve-CIPPSAMCredentialThumbprint {
    <#
    .SYNOPSIS
    Maps a Graph keyCredential customKeyIdentifier to a known thumbprint when possible
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $Credential,
        [System.Collections.Generic.List[string]]$KnownThumbprints
    )

    $Identifier = $Credential.customKeyIdentifier
    if ([string]::IsNullOrEmpty($Identifier)) {
        return $null
    }

    foreach ($Thumbprint in @($KnownThumbprints)) {
        if ([string]::IsNullOrEmpty($Thumbprint)) { continue }
        if ($Identifier -eq $Thumbprint) { return $Thumbprint }
        try {
            $AsBase64 = [Convert]::ToBase64String([Convert]::FromHexString($Thumbprint))
            if ($Identifier -eq $AsBase64) { return $Thumbprint }
        } catch {
            # Thumbprint was not valid hex — ignore
        }
    }

    # Graph often returns the hex thumbprint directly
    if ($Identifier -match '^[0-9A-Fa-f]{40}$') {
        return $Identifier.ToUpperInvariant()
    }

    return $null
}

function Test-CIPPSAMAppHasThumbprint {
    <#
    .SYNOPSIS
    Returns true when an app keyCredentials collection includes the given thumbprint
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $Credentials,
        [string]$Thumbprint
    )

    if ([string]::IsNullOrEmpty($Thumbprint)) {
        return $false
    }

    $Identifiers = @($Credentials.customKeyIdentifier)
    if ($Identifiers -contains $Thumbprint) {
        return $true
    }
    try {
        $AsBase64 = [Convert]::ToBase64String([Convert]::FromHexString($Thumbprint))
        return ($Identifiers -contains $AsBase64)
    } catch {
        return $false
    }
}
