function ConvertFrom-CIPPContainerImageRef {
    <#
    .SYNOPSIS
        Splits a linuxFxVersion or image reference into base, tag and digest.
    .DESCRIPTION
        Accepts 'DOCKER|ghcr.io/cyberdrain/cipp:dev@sha256:<hex>' and every shorter form (no tag,
        tag only, digest only). A ':' before the last '/' is a registry port, not a tag.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        ConvertFrom-CIPPContainerImageRef -Reference 'DOCKER|ghcr.io/cyberdrain/cipp:dev@sha256:abc'
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Reference)

    $Ref = ([string]$Reference).Trim() -replace '^DOCKER\|', ''
    $Digest = ''
    if ($Ref -match '^(.*)@(sha256:[0-9a-fA-F]+)$') {
        $Ref = $Matches[1]
        $Digest = $Matches[2].ToLowerInvariant()
    }
    $Tag = ''
    if ($Ref -match '^(.*/[^/:]+|[^/:]+):([^:/]+)$') {
        $Ref = $Matches[1]
        $Tag = $Matches[2]
    }
    $First = if ($Ref -match '^([^/]+)/') { $Matches[1] } else { '' }
    $Registry = if ($First -match '[.:]|^localhost$') { $First } else { '' }

    [pscustomobject]@{
        Base     = $Ref
        Tag      = $Tag
        Digest   = $Digest
        Registry = $Registry
    }
}
