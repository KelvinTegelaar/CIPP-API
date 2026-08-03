function Get-CIPPBrandingSettings {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Loads BrandingSettings, migrates legacy inline images into the Images table,
        and returns a hydrated customBranding object for the frontend and reports.
    #>
    [CmdletBinding()]
    param(
        [switch]$PersistMigration
    )

    $DefaultCoverStock = '/reportImages/soc.jpg'
    $AllowedCoverStock = @(
        'none',
        '/reportImages/soc.jpg',
        '/reportImages/board.jpg',
        '/reportImages/glasses.jpg',
        '/reportImages/working.jpg',
        '/reportImages/laptop.jpg',
        '/reportImages/city.jpg'
    )

    $Table = Get-CIPPTable -TableName 'Config'
    $Filter = "PartitionKey eq 'BrandingSettings'"
    $BrandingConfig = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.RowKey -eq 'BrandingSettings' }

    if (-not $BrandingConfig) {
        return [pscustomobject]@{
            colour         = '#F77F00'
            logoImageId    = $null
            logoImageIds   = @()
            coverStock     = $DefaultCoverStock
            coverImageId   = $null
            coverImageIds  = @()
            logo           = $null
            logoUploads    = @()
            coverImage     = $null
            coverUploads   = @()
        }
    }

    $Migrated = $false

    # Legacy inline logo -> Images / logo (+ seed logoImageIds)
    if ($BrandingConfig.logo -and "$($BrandingConfig.logo)" -match '^data:image\/' -and -not $BrandingConfig.logoImageId) {
        try {
            $Added = Add-CIPPImage -PartitionKey 'logo' -Data "$($BrandingConfig.logo)"
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageId' -Value $Added.id -Force
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageIds' -Value (ConvertTo-Json -InputObject @($Added.id) -Compress -AsArray) -Force
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logo' -Value $null -Force
            $Migrated = $true
        } catch {
            Write-Warning "Failed to migrate branding logo to Images table: $($_.Exception.Message)"
        }
    }

    # Seed logoImageIds from a lone logoImageId
    $ExistingLogoIds = ConvertTo-CIPPCoverImageIdList -Value $BrandingConfig.logoImageIds
    if ($null -eq $ExistingLogoIds) { $ExistingLogoIds = [string[]]@() }
    if ($ExistingLogoIds.Count -eq 0 -and $BrandingConfig.logoImageId -and "$($BrandingConfig.logoImageId)" -ne '') {
        $ExistingLogoIds = @("$($BrandingConfig.logoImageId)")
        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageIds' -Value (ConvertTo-Json -InputObject $ExistingLogoIds -Compress -AsArray) -Force
        $Migrated = $true
    }

    # Legacy coverUploads / coverImage -> Images / brandingCover
    $LegacyUploads = @()
    if ($BrandingConfig.coverUploads) {
        if ($BrandingConfig.coverUploads -is [string] -and "$($BrandingConfig.coverUploads)" -match '^data:image\/') {
            $LegacyUploads = @("$($BrandingConfig.coverUploads)")
        } else {
            $ParsedUploads = ConvertTo-CIPPCoverImageIdList -Value $BrandingConfig.coverUploads
            if ($null -eq $ParsedUploads) { $ParsedUploads = [string[]]@() }
            if ($ParsedUploads.Count -gt 0 -and $ParsedUploads[0] -match '^data:image\/') {
                $LegacyUploads = @($ParsedUploads | Where-Object { $_ -match '^data:image\/' })
            }
        }
    }
    if ($BrandingConfig.coverImage -and "$($BrandingConfig.coverImage)" -match '^data:image\/') {
        if ($LegacyUploads -notcontains "$($BrandingConfig.coverImage)") {
            $LegacyUploads = @("$($BrandingConfig.coverImage)") + $LegacyUploads
        }
    }

    $ExistingCoverIds = ConvertTo-CIPPCoverImageIdList -Value $BrandingConfig.coverImageIds
    if ($null -eq $ExistingCoverIds) { $ExistingCoverIds = [string[]]@() }
    $HasLegacyDataUrls = $LegacyUploads.Count -gt 0 -and $LegacyUploads[0] -match '^data:image\/'
    if ($HasLegacyDataUrls -and $ExistingCoverIds.Count -eq 0) {
        $NewCoverIds = [System.Collections.Generic.List[string]]::new()
        foreach ($Upload in $LegacyUploads) {
            try {
                $Added = Add-CIPPImage -PartitionKey 'brandingCover' -Data $Upload
                $NewCoverIds.Add($Added.id) | Out-Null
            } catch {
                Write-Warning "Failed to migrate branding cover to Images table: $($_.Exception.Message)"
            }
        }
        if ($NewCoverIds.Count -gt 0) {
            $SelectedCoverId = $null
            if ($BrandingConfig.coverImage -and "$($BrandingConfig.coverImage)" -match '^data:image\/') {
                $SelectedCoverId = $NewCoverIds[0]
            }
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageIds' -Value (ConvertTo-Json -InputObject @($NewCoverIds.ToArray()) -Compress -AsArray) -Force
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageId' -Value $SelectedCoverId -Force
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImage' -Value $null -Force
            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverUploads' -Value '[]' -Force
            $Migrated = $true
            $ExistingCoverIds = @($NewCoverIds)
        }
    }

    if ($Migrated -and $PersistMigration) {
        $BrandingConfig.PartitionKey = 'BrandingSettings'
        $BrandingConfig.RowKey = 'BrandingSettings'
        foreach ($LegacyProp in @('logo', 'coverImage', 'coverUploads', 'logoUploads')) {
            if ($BrandingConfig.PSObject.Properties.Name -contains $LegacyProp) {
                $BrandingConfig | Add-Member -MemberType NoteProperty -Name $LegacyProp -Value $null -Force
            }
        }
        Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
    }

    $CoverStock = $BrandingConfig.coverStock
    if (-not $CoverStock -or $AllowedCoverStock -notcontains $CoverStock) {
        $CoverStock = $DefaultCoverStock
    }

    $LogoImageId = if ($BrandingConfig.logoImageId) { "$($BrandingConfig.logoImageId)" } else { $null }
    $CoverImageId = if ($BrandingConfig.coverImageId) { "$($BrandingConfig.coverImageId)" } else { $null }
    if ($LogoImageId -eq '') { $LogoImageId = $null }
    if ($CoverImageId -eq '') { $CoverImageId = $null }

    $LogoImageIds = ConvertTo-CIPPCoverImageIdList -Value $BrandingConfig.logoImageIds
    if ($null -eq $LogoImageIds) { $LogoImageIds = [string[]]@() }
    if ($LogoImageIds.Count -eq 0 -and $ExistingLogoIds.Count -gt 0) {
        $LogoImageIds = [string[]]@($ExistingLogoIds)
    }
    if ($LogoImageIds.Count -eq 0 -and $LogoImageId) {
        $LogoImageIds = [string[]]@($LogoImageId)
    }

    $CoverImageIds = ConvertTo-CIPPCoverImageIdList -Value $BrandingConfig.coverImageIds
    if ($null -eq $CoverImageIds) { $CoverImageIds = [string[]]@() }
    if ($CoverImageIds.Count -eq 0 -and $ExistingCoverIds.Count -gt 0) {
        $CoverImageIds = [string[]]@($ExistingCoverIds)
    }

    $LogoMap = @{}
    if ($LogoImageIds.Count -eq 1) {
        $OneLogo = Get-CIPPImage -PartitionKey 'logo' -Id ([string]$LogoImageIds[0])
        if ($OneLogo) {
            $LogoMap[[string]$LogoImageIds[0]] = $OneLogo
        }
    } elseif ($LogoImageIds.Count -gt 1) {
        $FetchedLogos = Get-CIPPImage -PartitionKey 'logo' -Id ([string[]]$LogoImageIds)
        if ($FetchedLogos -is [hashtable]) {
            $LogoMap = $FetchedLogos
        }
    }

    $ResolvedLogoIds = [System.Collections.Generic.List[string]]::new()
    $LogoUploads = [System.Collections.Generic.List[string]]::new()
    foreach ($Lid in $LogoImageIds) {
        if ($LogoMap -is [hashtable] -and $LogoMap.ContainsKey($Lid) -and $LogoMap[$Lid].data) {
            $ResolvedLogoIds.Add($Lid) | Out-Null
            $LogoUploads.Add($LogoMap[$Lid].data) | Out-Null
        }
    }
    $LogoImageIds = @($ResolvedLogoIds)
    if ($LogoImageId -and $LogoImageIds -notcontains $LogoImageId) {
        $LogoImageId = $null
    }

    $LogoData = $null
    if ($LogoImageId -and $LogoMap -is [hashtable] -and $LogoMap.ContainsKey($LogoImageId) -and $LogoMap[$LogoImageId].data) {
        $LogoData = $LogoMap[$LogoImageId].data
    } elseif ($BrandingConfig.logo -and "$($BrandingConfig.logo)" -match '^data:image\/' -and -not $LogoImageId) {
        $LogoData = "$($BrandingConfig.logo)"
    }

    $CoverMap = @{}
    if ($CoverImageIds.Count -eq 1) {
        $OneCover = Get-CIPPImage -PartitionKey 'brandingCover' -Id ([string]$CoverImageIds[0])
        if ($OneCover) {
            $CoverMap[[string]$CoverImageIds[0]] = $OneCover
        }
    } elseif ($CoverImageIds.Count -gt 1) {
        $Fetched = Get-CIPPImage -PartitionKey 'brandingCover' -Id ([string[]]$CoverImageIds)
        if ($Fetched -is [hashtable]) {
            $CoverMap = $Fetched
        }
    }

    $ResolvedCoverIds = [System.Collections.Generic.List[string]]::new()
    $CoverUploads = [System.Collections.Generic.List[string]]::new()
    foreach ($Cid in $CoverImageIds) {
        if ($CoverMap -is [hashtable] -and $CoverMap.ContainsKey($Cid) -and $CoverMap[$Cid].data) {
            $ResolvedCoverIds.Add($Cid) | Out-Null
            $CoverUploads.Add($CoverMap[$Cid].data) | Out-Null
        }
    }
    $CoverImageIds = @($ResolvedCoverIds)
    if ($CoverImageId -and $CoverImageIds -notcontains $CoverImageId) {
        $CoverImageId = $null
    }

    $CoverImageData = $null
    if ($CoverImageId -and $CoverMap -is [hashtable] -and $CoverMap.ContainsKey($CoverImageId) -and $CoverMap[$CoverImageId].data) {
        $CoverImageData = $CoverMap[$CoverImageId].data
    } elseif ($BrandingConfig.coverImage -and "$($BrandingConfig.coverImage)" -match '^data:image\/' -and -not $CoverImageId) {
        $CoverImageData = "$($BrandingConfig.coverImage)"
    }

    return [pscustomobject]@{
        colour        = if ($BrandingConfig.colour) { $BrandingConfig.colour } else { '#F77F00' }
        logoImageId   = $LogoImageId
        logoImageIds  = [string[]]@($LogoImageIds)
        coverStock    = $CoverStock
        coverImageId  = $CoverImageId
        coverImageIds = [string[]]@($CoverImageIds)
        logo          = $LogoData
        logoUploads   = [string[]]@($LogoUploads)
        coverImage    = $CoverImageData
        coverUploads  = [string[]]@($CoverUploads)
    }
}
