function Get-CIPPSAMCertificateVersions {
    <#
    .SYNOPSIS
    Loads current, previous, and historical SAM certificate thumbprints from storage

    .DESCRIPTION
    Reads version history for the SAMCertificate Key Vault secret (or DevSecrets in local
    mode). Current and previous are the keep-set for Entra keyCredentials; older loaded
    versions supply HistoricalThumbprints used to prove a credential was CIPP-generated
    before removing it. Caps full PFX materialization at 50 newest enabled versions.

    .PARAMETER Name
    Storage name. Defaults to SAMCertificate.

    .PARAMETER VaultName
    Key Vault name. Derived via Get-CippKeyVaultName when omitted.

    .PARAMETER MaxVersions
    Maximum enabled versions to materialize. Defaults to 50.

    .EXAMPLE
    $Versions = Get-CIPPSAMCertificateVersions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name = 'SAMCertificate',

        [Parameter(Mandatory = $false)]
        [string]$VaultName,

        [Parameter(Mandatory = $false)]
        [int]$MaxVersions = 50
    )

    $Empty = [PSCustomObject]@{
        Current               = $null
        Previous              = $null
        HistoricalThumbprints = [string[]]@()
        AllKnownThumbprints   = [string[]]@()
    }

    $Materialized = [System.Collections.Generic.List[object]]::new()

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        if ($Secret.$Name) {
            $CurrentInfo = ConvertTo-CIPPSAMCertificateInfo -PfxBase64 $Secret.$Name
            if ($CurrentInfo) { $Materialized.Add($CurrentInfo) }
        }
        $PreviousProp = "${Name}Previous"
        if ($Secret.$PreviousProp) {
            $PreviousInfo = ConvertTo-CIPPSAMCertificateInfo -PfxBase64 $Secret.$PreviousProp
            if ($PreviousInfo) { $Materialized.Add($PreviousInfo) }
        }
    } else {
        if (-not $VaultName) {
            $VaultName = Get-CippKeyVaultName
            if (-not $VaultName) {
                throw 'VaultName not provided and could not be derived (WEBSITE_SITE_NAME / WEBSITE_DEPLOYMENT_ID not set)'
            }
        }

        $Token = Get-CIPPAzIdentityToken -ResourceUrl 'https://vault.azure.net'
        $Headers = @{ Authorization = "Bearer $Token" }

        $VersionEntries = [System.Collections.Generic.List[object]]::new()
        $ListUri = "https://$VaultName.vault.azure.net/secrets/$Name/versions?api-version=7.4"
        try {
            while ($ListUri) {
                $ListResponse = Invoke-CIPPRestMethod -Uri $ListUri -Headers $Headers -Method Get -ErrorAction Stop
                foreach ($Entry in @($ListResponse.value)) {
                    $VersionEntries.Add($Entry)
                }
                $ListUri = $ListResponse.nextLink
            }
        } catch {
            if ($_.Exception.Message -match 'SecretNotFound|404') {
                return $Empty
            }
            throw
        }

        $Enabled = @(
            $VersionEntries |
                Where-Object { $_.attributes.enabled -ne $false } |
                Sort-Object { $_.attributes.created } -Descending |
                Select-Object -First $MaxVersions
        )

        foreach ($Entry in $Enabled) {
            $VersionId = ($Entry.id -split '/')[-1]
            try {
                $SecretUri = "https://$VaultName.vault.azure.net/secrets/$Name/$VersionId`?api-version=7.4"
                $SecretResponse = Invoke-CIPPRestMethod -Uri $SecretUri -Headers $Headers -Method Get -ErrorAction Stop
                if ([string]::IsNullOrEmpty($SecretResponse.value)) { continue }
                $Info = ConvertTo-CIPPSAMCertificateInfo -PfxBase64 $SecretResponse.value
                if ($Info) { $Materialized.Add($Info) }
            } catch {
                Write-Warning "Could not materialize SAM certificate version $VersionId : $($_.Exception.Message)"
            }
        }
    }

    if ($Materialized.Count -eq 0) {
        return $Empty
    }

    $Current = $Materialized[0]
    $Previous = if ($Materialized.Count -gt 1) { $Materialized[1] } else { $null }
    $Historical = [System.Collections.Generic.List[string]]::new()
    for ($i = 2; $i -lt $Materialized.Count; $i++) {
        if ($Materialized[$i].Thumbprint) {
            $Historical.Add($Materialized[$i].Thumbprint)
        }
    }

    $AllKnown = [System.Collections.Generic.List[string]]::new()
    if ($Current.Thumbprint) { $AllKnown.Add($Current.Thumbprint) }
    if ($Previous.Thumbprint) { $AllKnown.Add($Previous.Thumbprint) }
    foreach ($Tp in $Historical) { $AllKnown.Add($Tp) }

    return [PSCustomObject]@{
        Current               = $Current
        Previous              = $Previous
        HistoricalThumbprints = @($Historical)
        AllKnownThumbprints   = @($AllKnown)
    }
}

function ConvertTo-CIPPSAMCertificateInfo {
    <#
    .SYNOPSIS
    Materializes a base64 PFX into thumbprint / public key metadata for SAM cert rotation
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PfxBase64
    )

    if ([string]::IsNullOrEmpty($PfxBase64)) {
        return $null
    }

    try {
        $PfxBytes = [Convert]::FromBase64String($PfxBase64)
        $KeyFlags = if ($IsLinux -or $IsMacOS) {
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        } else {
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet
        }
        $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $PfxBytes,
            [string]::Empty,
            $KeyFlags
        )
        try {
            $PublicKeyBase64 = [Convert]::ToBase64String(
                $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            )
            return [PSCustomObject]@{
                Certificate     = $Certificate
                Thumbprint      = $Certificate.Thumbprint
                NotBefore       = $Certificate.NotBefore.ToUniversalTime()
                NotAfter        = $Certificate.NotAfter.ToUniversalTime()
                PfxBase64       = $PfxBase64
                PublicKeyBase64 = $PublicKeyBase64
            }
        } catch {
            $Certificate.Dispose()
            throw
        }
    } catch {
        Write-Warning "Could not parse SAM certificate PFX: $($_.Exception.Message)"
        return $null
    }
}
