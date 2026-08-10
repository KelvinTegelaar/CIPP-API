function Get-CIPPBrandingPreset {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Returns named branding presets in the same shape as Get-CIPPBrandingSettings.
    .DESCRIPTION
        A preset is a complete set of report branding — colours, logo, cover, footer and
        watermark — that a report can be pointed at instead of the global settings. That is what
        lets one report go out with a cover image and full colour while another goes out plain.

        Presets deliberately reuse the same Images table entries as the global settings, so a
        preset selects from the logo and cover gallery rather than holding its own copies.

        Because presets are new there is no legacy inline-image migration here, unlike
        Get-CIPPBrandingSettings — a preset has only ever stored image ids.
    .PARAMETER Id
        Return only the preset with this RowKey. Omit for all presets.
    .PARAMETER SkipImageData
        Return image ids without resolving them to data URLs. Used by callers that only need
        names and colours, since image payloads are large.
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [switch]$SkipImageData
    )

    $Table = Get-CIPPTable -TableName 'Config'
    $Filter = if ($Id) {
        "PartitionKey eq 'BrandingPresets' and RowKey eq '$($Id.Replace("'","''"))'"
    } else {
        "PartitionKey eq 'BrandingPresets'"
    }

    $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    if ($Entities.Count -eq 0) { return @() }

    $LogoMap = @{}
    $CoverMap = @{}

    if (-not $SkipImageData) {
        # Resolve every preset's images in one read per kind rather than one per preset.
        $LogoIds = @($Entities.logoImageId | Where-Object { $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_" } | Select-Object -Unique)
        $CoverIds = @($Entities.coverImageId | Where-Object { $_ -and "$_".Trim() -ne '' } | ForEach-Object { "$_" } | Select-Object -Unique)

        if ($LogoIds.Count -eq 1) {
            $Single = Get-CIPPImage -PartitionKey 'logo' -Id ([string[]]$LogoIds)
            if ($Single) { $LogoMap[$LogoIds[0]] = $Single }
        } elseif ($LogoIds.Count -gt 1) {
            $Fetched = Get-CIPPImage -PartitionKey 'logo' -Id ([string[]]$LogoIds)
            if ($Fetched -is [hashtable]) { $LogoMap = $Fetched }
        }

        if ($CoverIds.Count -eq 1) {
            $Single = Get-CIPPImage -PartitionKey 'brandingCover' -Id ([string[]]$CoverIds)
            if ($Single) { $CoverMap[$CoverIds[0]] = $Single }
        } elseif ($CoverIds.Count -gt 1) {
            $Fetched = Get-CIPPImage -PartitionKey 'brandingCover' -Id ([string[]]$CoverIds)
            if ($Fetched -is [hashtable]) { $CoverMap = $Fetched }
        }
    }

    $Presets = foreach ($Entity in $Entities) {
        $LogoId = if ($Entity.logoImageId) { "$($Entity.logoImageId)" } else { $null }
        $CoverId = if ($Entity.coverImageId) { "$($Entity.coverImageId)" } else { $null }

        $LogoData = $null
        if ($LogoId -and $LogoMap -is [hashtable] -and $LogoMap.ContainsKey($LogoId)) {
            $LogoData = $LogoMap[$LogoId].data
        }
        $CoverData = $null
        if ($CoverId -and $CoverMap -is [hashtable] -and $CoverMap.ContainsKey($CoverId)) {
            $CoverData = $CoverMap[$CoverId].data
        }

        [pscustomobject]@{
            id               = "$($Entity.RowKey)"
            name             = if ($Entity.name) { "$($Entity.name)" } else { 'Untitled preset' }
            colour           = if ($Entity.colour) { "$($Entity.colour)" } else { '#F77F00' }
            secondaryColour  = if ($Entity.secondaryColour) { "$($Entity.secondaryColour)" } else { '' }
            logoImageId      = $LogoId
            logo             = $LogoData
            coverStock       = if ($Entity.coverStock) { "$($Entity.coverStock)" } else { 'none' }
            coverImageId     = $CoverId
            coverImage       = $CoverData
            footerText       = if ($Entity.footerText) { "$($Entity.footerText)" } else { '' }
            coverFooterText  = if ($Entity.coverFooterText) { "$($Entity.coverFooterText)" } else { '' }
            showFooter       = if ($null -eq $Entity.showFooter) { $true } else { [bool]$Entity.showFooter }
            showPageNumbers  = if ($null -eq $Entity.showPageNumbers) { $true } else { [bool]$Entity.showPageNumbers }
            watermarkText    = if ($Entity.watermarkText) { "$($Entity.watermarkText)" } else { '' }
            watermarkEnabled = if ($null -eq $Entity.watermarkEnabled) { $true } else { [bool]$Entity.watermarkEnabled }
        }
    }

    return @($Presets | Sort-Object -Property name)
}
