function Get-CIPPGHCRImageInfo {
    <#
    .SYNOPSIS
        Reads digest, version label and build date of a GHCR image tag.
    .DESCRIPTION
        The version label is set by CI (org.opencontainers.image.version) and matches $env:APP_VERSION
        in the running container. AuthHeader is returned so callers can reuse the anonymous pull token.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPGHCRImageInfo -ImagePath 'cyberdrain/cipp' -Tag 'dev'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    # Invoke-WebRequest returns byte[] when GHCR omits a charset; decode before ConvertFrom-Json.
    function ConvertFrom-RawJson($Content) {
        if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
        return $Content | ConvertFrom-Json
    }

    $TokenResp = Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:${ImagePath}:pull" -Method GET -ErrorAction Stop
    $AuthHeader = @{ Authorization = "Bearer $($TokenResp.token)" }
    $ManifestHeaders = $AuthHeader + @{ Accept = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' }

    $Resp = Invoke-WebRequest -Uri "https://ghcr.io/v2/$ImagePath/manifests/$Tag" -Method GET -Headers $ManifestHeaders -ErrorAction Stop
    $Digest = $Resp.Headers['Docker-Content-Digest']
    if ($Digest -is [array]) { $Digest = $Digest[0] }
    $Manifest = ConvertFrom-RawJson $Resp.Content

    if ($Manifest.manifests) {
        $Child = $Manifest.manifests | Where-Object { $_.platform.architecture -eq 'amd64' -and $_.platform.os -eq 'linux' } | Select-Object -First 1
        if (-not $Child) { $Child = $Manifest.manifests | Select-Object -First 1 }
        $Manifest = ConvertFrom-RawJson (Invoke-WebRequest -Uri "https://ghcr.io/v2/$ImagePath/manifests/$($Child.digest)" -Method GET -Headers $ManifestHeaders -ErrorAction Stop).Content
    }

    $Version = $Manifest.annotations.'org.opencontainers.image.version'
    $Created = $Manifest.annotations.'org.opencontainers.image.created'
    if ((-not $Version -or -not $Created) -and $Manifest.config.digest) {
        try {
            $Config = Invoke-RestMethod -Uri "https://ghcr.io/v2/$ImagePath/blobs/$($Manifest.config.digest)" -Method GET -Headers $AuthHeader -ErrorAction Stop
            if (-not $Version) { $Version = $Config.config.Labels.'org.opencontainers.image.version' }
            if (-not $Created) { $Created = $Config.config.Labels.'org.opencontainers.image.created' }
        } catch {
            Write-Information "Could not read image config labels for $($ImagePath):$Tag - $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Digest     = [string]$Digest
        Version    = [string]$Version
        # ConvertFrom-Json yields a local DateTime; a bare string of it loses the zone.
        Created    = if ($Created -is [DateTime]) { $Created.ToUniversalTime().ToString('o') } else { [string]$Created }
        AuthHeader = $AuthHeader
    }
}
