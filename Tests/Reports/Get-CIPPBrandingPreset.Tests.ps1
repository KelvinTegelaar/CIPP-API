# Pester tests for Get-CIPPBrandingPreset.
#
# A preset is a complete branding set a report can be rendered against instead of the global
# settings. Reports read the returned object directly, so every field a report reads has to be
# present with a usable value even when the stored row predates it or never set it — a missing
# `showFooter` must come back as $true, not $null, or the report silently loses its footer.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPBrandingPreset.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPBrandingPreset.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:LastFilter = $Filter; return $script:Rows }
    function Get-CIPPImage {
        param([string]$PartitionKey, [string[]]$Id)
        $script:ImageRequests += , @{ PartitionKey = $PartitionKey; Id = @($Id) }
        if (@($Id).Count -eq 1) {
            if ($script:Images.ContainsKey($Id[0])) { return $script:Images[$Id[0]] }
            return $null
        }
        $Map = @{}
        foreach ($ImageId in $Id) {
            if ($script:Images.ContainsKey($ImageId)) { $Map[$ImageId] = $script:Images[$ImageId] }
        }
        return $Map
    }

    . $FunctionPath

    function New-PresetRow {
        param([hashtable]$Overrides = @{})
        $Row = @{
            PartitionKey = 'BrandingPresets'
            RowKey       = 'preset-1'
            name         = 'Client Facing'
            colour       = '#342858'
        }
        foreach ($Key in $Overrides.Keys) { $Row[$Key] = $Overrides[$Key] }
        return [pscustomobject]$Row
    }
}

Describe 'Get-CIPPBrandingPreset' {
    BeforeEach {
        $script:Rows = @()
        $script:Images = @{}
        $script:ImageRequests = @()
        $script:LastFilter = $null
    }

    Context 'No presets stored' {
        It 'returns an empty collection rather than $null' {
            $Result = Get-CIPPBrandingPreset
            @($Result).Count | Should -Be 0
        }
    }

    Context 'Defaults for fields a stored preset never set' {
        BeforeEach {
            $script:Rows = @(New-PresetRow)
        }

        It 'defaults showFooter to on, so a preset does not silently drop the footer' {
            (Get-CIPPBrandingPreset)[0].showFooter | Should -BeTrue
        }

        It 'defaults showPageNumbers to on' {
            (Get-CIPPBrandingPreset)[0].showPageNumbers | Should -BeTrue
        }

        It 'defaults the watermark toggle to on, since the text is what actually shows it' {
            # The toggle is a suppressor, not a second switch to find — a preset with no watermark
            # text still shows nothing, which is the guarantee that matters.
            (Get-CIPPBrandingPreset)[0].watermarkEnabled | Should -BeTrue
            (Get-CIPPBrandingPreset)[0].watermarkText | Should -Be ''
        }

        It 'returns an empty secondaryColour, which the renderer reads as "use the primary"' {
            (Get-CIPPBrandingPreset)[0].secondaryColour | Should -Be ''
        }

        It 'defaults coverStock to none' {
            (Get-CIPPBrandingPreset)[0].coverStock | Should -Be 'none'
        }

        It 'falls back to the CIPP orange when no colour was stored' {
            $script:Rows = @(New-PresetRow -Overrides @{ colour = $null })
            (Get-CIPPBrandingPreset)[0].colour | Should -Be '#F77F00'
        }

        It 'names an unnamed preset rather than returning a blank chip' {
            $script:Rows = @(New-PresetRow -Overrides @{ name = '' })
            (Get-CIPPBrandingPreset)[0].name | Should -Be 'Untitled preset'
        }
    }

    Context 'Stored values are preserved' {
        It 'round-trips every configured field' {
            $script:Rows = @(New-PresetRow -Overrides @{
                    secondaryColour  = '#006666'
                    footerText       = '[tenantName] — [date]'
                    showFooter       = $false
                    showPageNumbers  = $false
                    watermarkText    = 'DRAFT'
                    watermarkEnabled = $true
                    coverStock       = '/reportImages/city.jpg'
                })

            $Preset = (Get-CIPPBrandingPreset)[0]
            $Preset.secondaryColour | Should -Be '#006666'
            $Preset.footerText | Should -Be '[tenantName] — [date]'
            $Preset.showFooter | Should -BeFalse
            $Preset.showPageNumbers | Should -BeFalse
            $Preset.watermarkText | Should -Be 'DRAFT'
            $Preset.watermarkEnabled | Should -BeTrue
            $Preset.coverStock | Should -Be '/reportImages/city.jpg'
        }

        It 'exposes the row key as the id the frontend selects by' {
            $script:Rows = @(New-PresetRow)
            (Get-CIPPBrandingPreset)[0].id | Should -Be 'preset-1'
        }
    }

    Context 'Image hydration' {
        It 'resolves a logo and cover to their data URLs' {
            $script:Rows = @(New-PresetRow -Overrides @{ logoImageId = 'logo-1'; coverImageId = 'cover-1' })
            $script:Images = @{
                'logo-1'  = @{ id = 'logo-1'; data = 'data:image/png;base64,LOGO' }
                'cover-1' = @{ id = 'cover-1'; data = 'data:image/png;base64,COVER' }
            }

            $Preset = (Get-CIPPBrandingPreset)[0]
            $Preset.logo | Should -Be 'data:image/png;base64,LOGO'
            $Preset.coverImage | Should -Be 'data:image/png;base64,COVER'
        }

        It 'keeps the id but returns no data when the image has been deleted' {
            $script:Rows = @(New-PresetRow -Overrides @{ logoImageId = 'missing' })

            $Preset = (Get-CIPPBrandingPreset)[0]
            $Preset.logoImageId | Should -Be 'missing'
            $Preset.logo | Should -BeNullOrEmpty
        }

        It 'reads each image kind once for the whole set, not once per preset' {
            $script:Rows = @(
                New-PresetRow -Overrides @{ RowKey = 'a'; name = 'A'; logoImageId = 'logo-1' }
                New-PresetRow -Overrides @{ RowKey = 'b'; name = 'B'; logoImageId = 'logo-2' }
                New-PresetRow -Overrides @{ RowKey = 'c'; name = 'C'; logoImageId = 'logo-1' }
            )
            $script:Images = @{
                'logo-1' = @{ id = 'logo-1'; data = 'data:image/png;base64,ONE' }
                'logo-2' = @{ id = 'logo-2'; data = 'data:image/png;base64,TWO' }
            }

            Get-CIPPBrandingPreset | Out-Null

            $LogoReads = @($script:ImageRequests | Where-Object { $_.PartitionKey -eq 'logo' })
            $LogoReads.Count | Should -Be 1
            # Duplicated ids are collapsed before the read.
            $LogoReads[0].Id.Count | Should -Be 2
        }

        It 'skips image reads entirely with -SkipImageData' {
            $script:Rows = @(New-PresetRow -Overrides @{ logoImageId = 'logo-1'; coverImageId = 'cover-1' })

            $Preset = (Get-CIPPBrandingPreset -SkipImageData)[0]

            $script:ImageRequests.Count | Should -Be 0
            $Preset.logoImageId | Should -Be 'logo-1'
            $Preset.logo | Should -BeNullOrEmpty
        }
    }

    Context 'Filtering and ordering' {
        It 'filters to a single preset by id' {
            $script:Rows = @(New-PresetRow)
            Get-CIPPBrandingPreset -Id 'preset-1' | Out-Null
            $script:LastFilter | Should -BeLike "*RowKey eq 'preset-1'*"
        }

        It 'escapes a quote in the id rather than letting it close the filter' {
            $script:Rows = @()
            Get-CIPPBrandingPreset -Id "a' or RowKey eq 'b" | Out-Null
            $script:LastFilter | Should -BeLike "*a'' or RowKey eq ''b*"
        }

        It 'returns presets in name order so the picker is stable' {
            $script:Rows = @(
                New-PresetRow -Overrides @{ RowKey = 'z'; name = 'Zulu' }
                New-PresetRow -Overrides @{ RowKey = 'a'; name = 'Alpha' }
                New-PresetRow -Overrides @{ RowKey = 'm'; name = 'Mike' }
            )
            (Get-CIPPBrandingPreset).name | Should -Be @('Alpha', 'Mike', 'Zulu')
        }
    }
}
