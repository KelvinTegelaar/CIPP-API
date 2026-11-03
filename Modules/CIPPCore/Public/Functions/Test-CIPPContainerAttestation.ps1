function Test-CIPPContainerAttestation {
    <#
    .SYNOPSIS
    Verify the Sigstore build-provenance attestation of a GHCR container image.

    .DESCRIPTION
    Fetches the attestation bundle that CI pushed as an OCI referrer of the image digest,
    verifies it with CIPP.SigstoreVerify against the pinned Sigstore public-good chain, then
    checks the signing identity against the repository and the workflow expected for the tag.

    State is Verified, Failed (missing, invalid or wrong-identity attestation) or Unverifiable
    (registry unreachable, or signed by a CA this instance does not carry). Never throws.

    .EXAMPLE
    Test-CIPPContainerAttestation -ImagePath 'cyberdrain/cipp' -Digest 'sha256:fa58...' -Tag 'dev'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [Parameter(Mandatory = $true)][string]$Digest,
        [Parameter(Mandatory = $true)][string]$Tag,
        [hashtable]$AuthHeader
    )

    function ConvertTo-AttestationResult($State, $Reason, $Identity = '', $Commit = '') {
        [pscustomobject]@{ State = $State; Reason = $Reason; Identity = $Identity; Commit = $Commit }
    }
    function ConvertFrom-RawJson($Content) {
        if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
        return $Content | ConvertFrom-Json
    }

    $DigestHex = $Digest -replace '^sha256:', ''
    if ($DigestHex -notmatch '^[0-9a-fA-F]{64}$') {
        return ConvertTo-AttestationResult 'Failed' "Image digest '$Digest' is not a sha256 digest"
    }

    try {
        if (-not $AuthHeader) {
            $TokenResp = Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:${ImagePath}:pull" -Method GET -ErrorAction Stop
            $AuthHeader = @{ Authorization = "Bearer $($TokenResp.token)" }
        }
        $Accept = 'application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json'
        $Headers = $AuthHeader + @{ Accept = $Accept }

        # The referrer tag schema (sha256-<hex>) is how attest-build-provenance publishes the bundle.
        $Index = ConvertFrom-RawJson (Invoke-WebRequest -Uri "https://ghcr.io/v2/$ImagePath/manifests/sha256-$DigestHex" -Method GET -Headers $Headers -ErrorAction Stop).Content
        $Ref = $Index.manifests | Where-Object { $_.artifactType -like 'application/vnd.dev.sigstore.bundle*' } | Select-Object -First 1
        if (-not $Ref) {
            return ConvertTo-AttestationResult 'Failed' 'No Sigstore attestation is published for this image'
        }
        $BundleManifest = ConvertFrom-RawJson (Invoke-WebRequest -Uri "https://ghcr.io/v2/$ImagePath/manifests/$($Ref.digest)" -Method GET -Headers $Headers -ErrorAction Stop).Content
        $BundleContent = (Invoke-WebRequest -Uri "https://ghcr.io/v2/$ImagePath/blobs/$($BundleManifest.layers[0].digest)" -Method GET -Headers $AuthHeader -ErrorAction Stop).Content
        if ($BundleContent -is [byte[]]) { $BundleContent = [System.Text.Encoding]::UTF8.GetString($BundleContent) }
    } catch {
        $Status = [int]($_.Exception.Response.StatusCode ?? 0)
        if ($Status -eq 404) {
            return ConvertTo-AttestationResult 'Failed' 'No Sigstore attestation is published for this image'
        }
        return ConvertTo-AttestationResult 'Unverifiable' "Could not fetch attestation: $($_.Exception.Message)"
    }

    try {
        $TrustChain = Get-Content -Raw -Path (Join-Path $env:CIPPRootPath 'Config\sigstore-public-good-chain.pem') -ErrorAction Stop
        $Result = [CIPP.SigstoreVerify]::Verify([string]$BundleContent, $DigestHex, $TrustChain)
    } catch {
        return ConvertTo-AttestationResult 'Unverifiable' "Attestation verifier unavailable: $($_.Exception.Message)"
    }

    if (-not $Result.Verified) {
        # Private-repo builds are signed by GitHub's own Fulcio, whose rotating root is not carried here.
        if ($Result.Stage -eq 'Chain' -and $Result.LeafIssuer -notmatch 'O=sigstore\.dev') {
            return ConvertTo-AttestationResult 'Unverifiable' $Result.Reason
        }
        return ConvertTo-AttestationResult 'Failed' $Result.Reason
    }

    $ExpectedRepo = ($ImagePath -split '/')[0..1] -join '/'
    if ($Result.Repository -ne $ExpectedRepo) {
        return ConvertTo-AttestationResult 'Failed' "Image was built by $($Result.Repository), expected $ExpectedRepo" $Result.Identity $Result.Commit
    }

    $Expected = switch -Regex ($Tag) {
        '^latest$|^\d+\.\d+\.\d+' { @{ Workflow = '.github/workflows/release-container.yml'; Ref = '^refs/tags/' }; break }
        '^dev$' { @{ Workflow = '.github/workflows/dev-container.yml'; Ref = '^refs/heads/dev$' }; break }
        # Scheduled runs carry the default branch (main) as their ref; manual runs carry dev.
        '^nightly$' { @{ Workflow = '.github/workflows/nightly-container.yml'; Ref = '^refs/heads/(main|dev)$' }; break }
        default { @{ Workflow = '.github/workflows/preview-container.yml'; Ref = '' } }
    }
    if ($Result.Workflow -ne $Expected.Workflow -or ($Expected.Ref -and $Result.Ref -notmatch $Expected.Ref)) {
        return ConvertTo-AttestationResult 'Failed' "Image for tag '$Tag' was built by $($Result.Workflow)@$($Result.Ref), expected $($Expected.Workflow)" $Result.Identity $Result.Commit
    }

    return ConvertTo-AttestationResult 'Verified' "Built by $($Result.Identity)" $Result.Identity $Result.Commit
}
