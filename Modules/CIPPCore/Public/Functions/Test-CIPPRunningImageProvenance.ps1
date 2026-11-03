function Test-CIPPRunningImageProvenance {
    <#
    .SYNOPSIS
        Records whether the image this instance booted from is pinned and attested.
    .DESCRIPTION
        Reads the digest pinned in the site's linuxFxVersion, verifies its attestation, and requires
        the attested commit to match the running build. Stores RunningAttestationState ('Verified',
        'Failed', 'Unverifiable' or 'Unpinned'), RunningAttestationReason and RunningDigest on the
        ContainerUpdateSettings UpdateConfig row without touching its other fields.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Test-CIPPRunningImageProvenance
    #>
    [CmdletBinding()]
    param()

    try {
        $Subscription = Get-CIPPAzFunctionAppSubId
        $SiteName = $env:WEBSITE_SITE_NAME
        $RGName = if ($SiteName) { Get-CIPPFunctionAppResourceGroup -SiteName $SiteName }
        if (-not ($Subscription -and $RGName -and $SiteName)) {
            Write-Information '[Provenance] No App Service context - running image not checked'
            return
        }
        $Uri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/config/web?api-version=2024-11-01"
        $Image = ConvertFrom-CIPPContainerImageRef -Reference (New-CIPPAzRestRequest -Uri $Uri -Method GET).properties.linuxFxVersion

        if (-not $Image.Digest) {
            $State = 'Unpinned'
            $Reason = 'The site configuration names a tag, not a digest, so a restart pulls whatever the tag points at.'
        } elseif ($Image.Registry -ne 'ghcr.io') {
            $State = 'Unverifiable'
            $Reason = "Provenance can only be verified for GHCR images, not $($Image.Base)"
        } else {
            $ImagePath = $Image.Base -replace '^ghcr\.io/', ''
            $Tag = if ($Image.Tag) { $Image.Tag } else { [string]$env:IMAGE_TAG }
            $Attestation = Test-CIPPContainerAttestation -ImagePath $ImagePath -Digest $Image.Digest -Tag $Tag
            $State = [string]$Attestation.State
            $Reason = [string]$Attestation.Reason
            if ($State -eq 'Verified' -and $Attestation.Commit -ne $env:COMMIT_SHA) {
                $State = 'Failed'
                $Reason = "The pinned image's attested commit $($Attestation.Commit) does not match the running build $($env:COMMIT_SHA)."
            }
        }

        $Table = Get-CIPPTable -tablename 'ContainerUpdateSettings'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
        if (-not $Row) { $Row = [pscustomobject]@{ PartitionKey = 'Settings'; RowKey = 'UpdateConfig' } }
        $Row | Add-Member -NotePropertyName RunningAttestationState -NotePropertyValue $State -Force
        $Row | Add-Member -NotePropertyName RunningAttestationReason -NotePropertyValue $Reason -Force
        $Row | Add-Member -NotePropertyName RunningDigest -NotePropertyValue ([string]$Image.Digest) -Force
        Add-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null
        Write-Information "[Provenance] Running image: $State $Reason"
    } catch {
        Write-Information "[Provenance] Running image check failed (non-fatal): $($_.Exception.Message)"
    }
}
