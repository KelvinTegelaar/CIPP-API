# Pester tests for the Catalog branch of Compare-CIPPIntuneObject and the definition index
# behind it.
#
# Regression under test: the Catalog branch read and parsed Config/intuneCollection.json - 18MB,
# ~18,000 definitions - on every call, which is once per Intune template, per tenant. Each parse
# retained several hundred MB of managed heap, and eight background workers comparing concurrently
# cleared the container's 2,398MB DOTNET_GCHeapHardLimit. The comparison then died with an
# OutOfMemoryException that Invoke-CIPPStandardIntuneTemplate caught and reported to the technician
# as drift ("Comparison failed: Exception of type 'System.OutOfMemoryException' was thrown.").
#
# Get-CIPPIntuneDefinitionIndex now projects the two things a comparison actually uses - the
# display name and the id -> display name option map - once per process. These tests pin the
# caching, the invalidation, and the label resolution the option lookup replaced.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneDefinitionIndex.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

    # Point CIPPRootPath at a throwaway tree holding a small stand-in collection, so these tests do
    # not depend on the shipped 18MB file. The target path is built with the same expression the
    # function reads with, and the parent is derived from that string, so the test and the function
    # agree on where the file lives on both Windows and Linux.
    $script:FakeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "cipp-defidx-$([guid]::NewGuid())"
    $script:CollectionPath = "$script:FakeRoot\Config\intuneCollection.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $script:CollectionPath) -Force | Out-Null
    $env:CIPPRootPath = $script:FakeRoot

    function Set-FakeCollection {
        param([string]$ToggleLabel = 'Toggle Setting', [string]$OnLabel = 'On')
        $Collection = @(
            @{ id = 'setting_toggle'; displayName = $ToggleLabel; description = 'x' * 200
                options = @(@{ id = 'setting_toggle_0'; displayName = 'Off' }, @{ id = 'setting_toggle_1'; displayName = $OnLabel })
            }
            @{ id = 'setting_plain'; displayName = 'Plain Setting'; helpText = 'y' * 200 }
            @{ id = 'setting_multi'; displayName = 'Multi Setting'
                options = @(@{ id = 'setting_multi_a'; displayName = 'Alpha' }, @{ id = 'setting_multi_b'; displayName = 'Bravo' })
            }
        )
        [System.IO.File]::WriteAllText($script:CollectionPath, ($Collection | ConvertTo-Json -Depth 10 -Compress))
        # The cache is keyed on length and last write time; clear it so each test starts honest.
        Remove-Variable -Name CIPPIntuneDefinitionIndex, CIPPIntuneDefinitionIndexStamp -Scope Script -ErrorAction SilentlyContinue
    }

    function New-CatalogSetting {
        param($DefinitionId, $Type, $Value)
        switch ($Type) {
            'choice' { @{ settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                        settingDefinitionId = $DefinitionId; choiceSettingValue = @{ value = $Value; children = @() } } } }
            'simple' { @{ settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                        settingDefinitionId = $DefinitionId; simpleSettingValue = @{ value = $Value } } } }
            'choiceCollection' { @{ settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingCollectionInstance'
                        settingDefinitionId = $DefinitionId; choiceSettingCollectionValue = @($Value | ForEach-Object { @{ value = $_ } }) } } }
        }
    }

    function New-CatalogPolicy {
        param([object[]]$Settings)
        [pscustomobject]@{ settings = @($Settings) }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:FakeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-CIPPIntuneDefinitionIndex' {
    BeforeEach { Set-FakeCollection }

    It 'indexes every definition by id' {
        $Index = Get-CIPPIntuneDefinitionIndex
        $Index.Count | Should -Be 3
        $Index['setting_plain'].displayName | Should -Be 'Plain Setting'
    }

    It 'projects options as an id -> display name map' {
        $Index = Get-CIPPIntuneDefinitionIndex
        $Index['setting_toggle'].options['setting_toggle_1'] | Should -Be 'On'
        $Index['setting_toggle'].options['setting_toggle_0'] | Should -Be 'Off'
    }

    It 'leaves options null for definitions that carry none' {
        (Get-CIPPIntuneDefinitionIndex)['setting_plain'].options | Should -BeNullOrEmpty
    }

    It 'matches ids case-insensitively, the way the -eq comparisons it replaced did' {
        (Get-CIPPIntuneDefinitionIndex)['SETTING_TOGGLE'].displayName | Should -Be 'Toggle Setting'
    }

    It 'returns null for a missing key rather than throwing' {
        { (Get-CIPPIntuneDefinitionIndex)['not_a_real_definition'] } | Should -Not -Throw
        (Get-CIPPIntuneDefinitionIndex)['not_a_real_definition'] | Should -BeNullOrEmpty
    }

    It 'hands back the same instance on a second call instead of reparsing' {
        $First = Get-CIPPIntuneDefinitionIndex
        $Second = Get-CIPPIntuneDefinitionIndex
        [object]::ReferenceEquals($First, $Second) | Should -BeTrue
    }

    It 'rebuilds when the collection on disk changes' {
        (Get-CIPPIntuneDefinitionIndex)['setting_toggle'].displayName | Should -Be 'Toggle Setting'
        Set-FakeCollection -ToggleLabel 'Renamed Toggle Setting'
        (Get-CIPPIntuneDefinitionIndex)['setting_toggle'].displayName | Should -Be 'Renamed Toggle Setting'
    }

    It 'returns null when the collection is missing instead of throwing' {
        $env:CIPPRootPath = Join-Path ([System.IO.Path]::GetTempPath()) "cipp-defidx-absent-$([guid]::NewGuid())"
        Remove-Variable -Name CIPPIntuneDefinitionIndex, CIPPIntuneDefinitionIndexStamp -Scope Script -ErrorAction SilentlyContinue
        try {
            Get-CIPPIntuneDefinitionIndex | Should -BeNullOrEmpty
        } finally {
            $env:CIPPRootPath = $script:FakeRoot
        }
    }
}

Describe 'Compare-CIPPIntuneObject -CompareType Catalog' {
    BeforeEach { Set-FakeCollection }

    It 'reports no drift when the policies match' {
        $Policy = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'))
        Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $Policy -CompareType 'Catalog' | Should -BeNullOrEmpty
    }

    It 'renders choice values as their friendly option labels on both sides' {
        $Ref = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'))
        $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_0'))

        $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Ref -DifferenceObject $Diff -CompareType 'Catalog')
        $Result.Count | Should -Be 1
        $Result[0].Property | Should -Be 'Toggle Setting'
        $Result[0].ExpectedValue | Should -Be 'On'
        $Result[0].ReceivedValue | Should -Be 'Off'
    }

    It 'resolves every member of a choice collection and sorts the rendered list' {
        $Ref = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_multi' -Type 'choiceCollection' -Value @('setting_multi_b', 'setting_multi_a')))
        $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_multi' -Type 'choiceCollection' -Value @('setting_multi_a')))

        $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Ref -DifferenceObject $Diff -CompareType 'Catalog')
        $Result[0].ExpectedValue | Should -Be 'Alpha, Bravo'
        $Result[0].ReceivedValue | Should -Be 'Alpha'
    }

    It 'keeps the raw value when it matches no option' {
        $Ref = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'value_with_no_option'))
        $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'))

        $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Ref -DifferenceObject $Diff -CompareType 'Catalog')
        $Result[0].ExpectedValue | Should -Be 'value_with_no_option'
        $Result[0].ReceivedValue | Should -Be 'On'
    }

    It 'falls back to the setting id when the definition is not in the collection' {
        $Ref = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_not_shipped' -Type 'simple' -Value '1'))
        $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_not_shipped' -Type 'simple' -Value '2'))

        $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Ref -DifferenceObject $Diff -CompareType 'Catalog')
        $Result[0].Property | Should -Be 'setting_not_shipped'
        $Result[0].ExpectedValue | Should -Be '1'
        $Result[0].ReceivedValue | Should -Be '2'
    }

    It 'flags a setting present on only one side' {
        $Ref = New-CatalogPolicy @(
            (New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'),
            (New-CatalogSetting -DefinitionId 'setting_plain' -Type 'simple' -Value '300')
        )
        $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'))

        $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Ref -DifferenceObject $Diff -CompareType 'Catalog')
        $Result.Count | Should -Be 1
        $Result[0].Property | Should -Be 'Plain Setting'
        $Result[0].ExpectedValue | Should -Be '300'
        $Result[0].ReceivedValue | Should -BeNullOrEmpty
    }

    It 'does not reparse the collection once it is cached' {
        $Policy = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_1'))
        Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $Policy -CompareType 'Catalog' | Out-Null

        # Deleting the file mid-run proves the second comparison never went back to disk.
        Remove-Item -LiteralPath $script:CollectionPath -Force
        try {
            $Diff = New-CatalogPolicy @((New-CatalogSetting -DefinitionId 'setting_toggle' -Type 'choice' -Value 'setting_toggle_0'))
            $Result = @(Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $Diff -CompareType 'Catalog')
            $Result[0].ExpectedValue | Should -Be 'On'
            $Result[0].ReceivedValue | Should -Be 'Off'
        } finally {
            Set-FakeCollection
        }
    }
}
