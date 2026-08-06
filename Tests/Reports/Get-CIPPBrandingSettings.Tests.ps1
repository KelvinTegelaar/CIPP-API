# Pester tests for Get-CIPPBrandingSettings.
#
# Reports read this object directly, so the defaults are the contract: an instance that upgraded
# into report chrome has no stored footer/watermark values, and the values returned for those decide
# whether its existing reports change appearance on the next render. They must not.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPBrandingSettings.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPBrandingSettings.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) return $script:Rows }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedEntity = $Entity }
    function Get-CIPPImage {
        param([string]$PartitionKey, [string[]]$Id)
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
    function Add-CIPPImage { param($PartitionKey, $Data) @{ id = 'migrated-1' } }
    function ConvertTo-CIPPCoverImageIdList {
        param($Value)
        if ($null -eq $Value -or $Value -eq '') { return , [string[]]@() }
        if ($Value -is [string]) {
            try {
                $Parsed = ConvertFrom-Json -InputObject $Value -ErrorAction Stop
                return , [string[]]@($Parsed | Where-Object { $_ })
            } catch {
                return , [string[]]@($Value)
            }
        }
        return , [string[]]@($Value | Where-Object { $_ })
    }

    . $FunctionPath

    function New-ConfigRow {
        param([hashtable]$Overrides = @{})
        $Row = @{
            PartitionKey = 'BrandingSettings'
            RowKey       = 'BrandingSettings'
            colour       = '#342858'
        }
        foreach ($Key in $Overrides.Keys) { $Row[$Key] = $Overrides[$Key] }
        return [pscustomobject]$Row
    }
}

Describe 'Get-CIPPBrandingSettings' {
    BeforeEach {
        $script:Rows = @()
        $script:Images = @{}
        $script:SavedEntity = $null
    }

    Context 'Nothing configured yet' {
        It 'returns report chrome defaults that leave existing reports unchanged' {
            $Result = Get-CIPPBrandingSettings

            $Result.colour | Should -Be '#F77F00'
            $Result.secondaryColour | Should -Be ''
            $Result.footerText | Should -Be ''
            $Result.showFooter | Should -BeTrue
            $Result.showPageNumbers | Should -BeTrue
            $Result.watermarkText | Should -Be ''
            # The toggle defaults on; with no text there is still no watermark, which is the
            # guarantee that keeps existing reports looking as they did.
            $Result.watermarkEnabled | Should -BeTrue
        }
    }

    Context 'Config row predating report chrome' {
        BeforeEach { $script:Rows = @(New-ConfigRow) }

        It 'reports no accent colour, which the renderer reads as "use the primary"' {
            (Get-CIPPBrandingSettings).secondaryColour | Should -Be ''
        }

        It 'leaves page numbers on, as they were before the setting existed' {
            (Get-CIPPBrandingSettings).showPageNumbers | Should -BeTrue
        }

        It 'leaves no watermark text, so no existing report gains a watermark' {
            $Result = Get-CIPPBrandingSettings
            $Result.watermarkText | Should -Be ''
            $Result.watermarkEnabled | Should -BeTrue
        }

        It 'keeps the configured brand colour' {
            (Get-CIPPBrandingSettings).colour | Should -Be '#342858'
        }
    }

    Context 'Configured report chrome' {
        It 'round-trips every stored value' {
            $script:Rows = @(New-ConfigRow -Overrides @{
                    secondaryColour  = '#006666'
                    footerText       = 'Prepared by Contoso'
                    showFooter       = $false
                    showPageNumbers  = $false
                    watermarkText    = 'CONFIDENTIAL'
                    watermarkEnabled = $true
                })

            $Result = Get-CIPPBrandingSettings
            $Result.secondaryColour | Should -Be '#006666'
            $Result.footerText | Should -Be 'Prepared by Contoso'
            $Result.showFooter | Should -BeFalse
            $Result.showPageNumbers | Should -BeFalse
            $Result.watermarkText | Should -Be 'CONFIDENTIAL'
            $Result.watermarkEnabled | Should -BeTrue
        }

        It 'distinguishes a stored false from an absent value' {
            # Both come back as $false from the table; only the stored one may switch the footer off.
            $script:Rows = @(New-ConfigRow -Overrides @{ showFooter = $false })
            (Get-CIPPBrandingSettings).showFooter | Should -BeFalse

            $script:Rows = @(New-ConfigRow)
            (Get-CIPPBrandingSettings).showFooter | Should -BeTrue
        }
    }

    Context 'Per-report default presets' {
        It 'returns an empty object when none are assigned' {
            $script:Rows = @(New-ConfigRow)
            @((Get-CIPPBrandingSettings).reportDefaults.PSObject.Properties).Count | Should -Be 0
        }

        It 'parses the stored JSON map back into an object the frontend can index' {
            $script:Rows = @(New-ConfigRow -Overrides @{
                    reportDefaults = '{"executive":"preset-1","sharing":"preset-2"}'
                })

            $Defaults = (Get-CIPPBrandingSettings).reportDefaults
            $Defaults.executive | Should -Be 'preset-1'
            $Defaults.sharing | Should -Be 'preset-2'
        }

        It 'ignores an unparseable map rather than failing the whole settings read' {
            # A broken default is worth far less than the rest of the branding.
            $script:Rows = @(New-ConfigRow -Overrides @{ reportDefaults = '{not json' })

            $Result = Get-CIPPBrandingSettings
            @($Result.reportDefaults.PSObject.Properties).Count | Should -Be 0
            $Result.colour | Should -Be '#342858'
        }
    }

    Context 'Cover stock' {
        It 'falls back to the default stock when the stored value is not one we ship' {
            $script:Rows = @(New-ConfigRow -Overrides @{ coverStock = 'https://evil.example/x.jpg' })
            (Get-CIPPBrandingSettings).coverStock | Should -Be '/reportImages/soc.jpg'
        }

        It 'keeps an explicit none' {
            $script:Rows = @(New-ConfigRow -Overrides @{ coverStock = 'none' })
            (Get-CIPPBrandingSettings).coverStock | Should -Be 'none'
        }
    }
}
