function Get-CIPPSAMCredentialOwner {
    <#
    .SYNOPSIS
        Classifies a CIPP-SAM credential as thisInstance, otherCipp, external or unknown.
    .DESCRIPTION
        Pure helper: no storage or Graph calls. A CIPP-named secret is 'unknown' rather than
        'otherCipp' while this instance has no tracked SecretKeyId, because it may be our own.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$KeyId,
        [string]$DisplayName,
        [ValidateSet('Secret', 'Certificate')]
        [string]$Type = 'Secret',
        [string]$Thumbprint,
        [string]$OwnSecretKeyId,
        [string]$OwnThumbprint
    )

    if ($Type -eq 'Secret' -and $OwnSecretKeyId -and $KeyId -eq $OwnSecretKeyId) { return 'thisInstance' }
    if ($Type -eq 'Certificate' -and $OwnThumbprint -and $Thumbprint -eq $OwnThumbprint) { return 'thisInstance' }

    $IsCippName = $DisplayName -in @('CIPPInstall', 'UpdateTokens') -or $DisplayName -like 'CIPP*'
    if (-not $IsCippName) { return 'external' }
    # Certificates are always tracked by thumbprint, so only secrets can be unattributed.
    if ($Type -eq 'Secret' -and -not $OwnSecretKeyId) { return 'unknown' }
    return 'otherCipp'
}
