# Data-driven proof that dropping the picker's rawData snapshot changes nothing a standard reads.
#
# Push-CIPPStandard strips rawData before handing settings to a standard. The claim that needs
# holding is not "it works for Intune templates" but "it is a no-op for all 197 standards", so this
# builds a settings object for every standard from its real addedComponent schema in
# Config/standards.json - every field type, every autoComplete, single and multi-select - and
# asserts the stripped result is byte-identical to the same settings built without a snapshot in the
# first place.
#
# The expected value is constructed independently rather than by re-running the function, so this
# cannot pass by agreeing with itself.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    $FunctionPath = Get-ChildItem -Path (Join-Path $BackendRoot 'Modules') -Recurse -Filter 'Remove-CIPPStandardSettingsRawData.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPStandardSettingsRawData.ps1 under Modules/' }
    . $FunctionPath

    $StandardsJson = Join-Path $BackendRoot 'Config/standards.json'
    if (-not (Test-Path $StandardsJson)) { throw "Could not locate $StandardsJson" }
    $script:AllStandards = @(Get-Content $StandardsJson -Raw | ConvertFrom-Json)

    # A value for one addedComponent. -WithRawData produces what the form actually saves; without it
    # produces the same selection minus the snapshot, which is the expected result of stripping.
    # rawData is added last so property order matches on both sides.
    function New-ComponentValue {
        param($Component, [switch]$WithRawData)

        switch ($Component.type) {
            'autoComplete' {
                $Build = {
                    param([string]$Suffix)
                    $Selection = [pscustomobject]@{
                        label       = "Label$Suffix"
                        value       = "value$Suffix"
                        addedFields = [pscustomobject]@{ package = 'baseline'; templates = @('t1', 't2') }
                    }
                    if ($WithRawData) {
                        # The whole API row, as CippAutocomplete attaches it.
                        $Selection | Add-Member -NotePropertyName 'rawData' -NotePropertyValue ([pscustomobject]@{
                                RowKey      = "value$Suffix"
                                Displayname = "Label$Suffix"
                                RAWJson     = '{"platforms":"windows10","settings":[' + ('{"x":"' + ('y' * 300) + '"},') * 5 + '{}]}'
                            })
                    }
                    $Selection
                }
                if ($Component.multiple) { return @((& $Build 'A'), (& $Build 'B')) }
                return (& $Build '')
            }
            'number' { return 42 }
            'switch' { return $true }
            'radio' { return 'AllDevices' }
            'select' { return 'Enabled' }
            'AdminRolesMultiSelect' { return @('Global Administrator') }
            'CountryCodeMultiSelect' { return @('NZ', 'AU') }
            'LanguageCodeMultiSelect' { return @('en-NZ') }
            'TimezoneSelect' { return 'Pacific/Auckland' }
            default { return "text-$($Component.name)" }
        }
    }

    # A full settings object for one standard, mirroring what Get-CIPPStandards emits.
    function New-SettingsForStandard {
        param($Standard, [switch]$WithRawData)

        $Settings = [pscustomobject]@{}
        foreach ($Component in @($Standard.addedComponent)) {
            if (-not $Component.name) { continue }
            $Value = if ($WithRawData) {
                New-ComponentValue -Component $Component -WithRawData
            } else {
                New-ComponentValue -Component $Component
            }
            $Settings | Add-Member -NotePropertyName $Component.name -NotePropertyValue $Value -Force
        }
        # The action booleans Convert-SingleStandardObject adds, plus the template id.
        $Settings | Add-Member -NotePropertyName 'remediate' -NotePropertyValue $true -Force
        $Settings | Add-Member -NotePropertyName 'alert' -NotePropertyValue $false -Force
        $Settings | Add-Member -NotePropertyName 'report' -NotePropertyValue $true -Force
        $Settings | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue 'std-template-guid' -Force
        return $Settings
    }

    function ConvertTo-ComparableJson {
        param($Object)
        return ($Object | ConvertTo-Json -Depth 20 -Compress)
    }

    # Walks the result looking for any surviving snapshot.
    function Test-HasRawData {
        param($Value, [int]$Depth = 0)
        if ($Depth -gt 8 -or $null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $false }
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.Contains('rawData')) { return $true }
            foreach ($V in $Value.Values) { if (Test-HasRawData -Value $V -Depth ($Depth + 1)) { return $true } }
            return $false
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($V in $Value) { if (Test-HasRawData -Value $V -Depth ($Depth + 1)) { return $true } }
            return $false
        }
        foreach ($P in $Value.PSObject.Properties) {
            if ($P.Name -eq 'rawData') { return $true }
            if (Test-HasRawData -Value $P.Value -Depth ($Depth + 1)) { return $true }
        }
        return $false
    }
}

Describe 'Dropping rawData is a no-op for every standard' {
    It 'has standards to check' {
        @($script:AllStandards).Count | Should -BeGreaterThan 150
    }

    It 'leaves every other setting byte-identical, for all standards' {
        $Mismatches = [System.Collections.Generic.List[string]]::new()

        foreach ($Standard in $script:AllStandards) {
            $WithRaw = New-SettingsForStandard -Standard $Standard -WithRawData
            $Expected = New-SettingsForStandard -Standard $Standard

            $Actual = Remove-CIPPStandardSettingsRawData -Settings $WithRaw

            if ((ConvertTo-ComparableJson $Actual) -ne (ConvertTo-ComparableJson $Expected)) {
                $Mismatches.Add($Standard.name)
            }
        }

        $Mismatches -join ', ' | Should -BeNullOrEmpty
    }

    It 'removes the snapshot from every standard that has a picker' {
        $Survivors = [System.Collections.Generic.List[string]]::new()
        $Checked = 0

        foreach ($Standard in $script:AllStandards) {
            $HasAutocomplete = @($Standard.addedComponent | Where-Object { $_.type -eq 'autoComplete' -and $_.name }).Count -gt 0
            if (-not $HasAutocomplete) { continue }
            $Checked++

            $Actual = Remove-CIPPStandardSettingsRawData -Settings (New-SettingsForStandard -Standard $Standard -WithRawData)
            if (Test-HasRawData -Value $Actual) { $Survivors.Add($Standard.name) }
        }

        $Checked | Should -BeGreaterThan 50 -Because 'the sweep should actually reach the picker standards'
        $Survivors -join ', ' | Should -BeNullOrEmpty
    }

    It 'keeps label, value and addedFields on every selection' {
        $Broken = [System.Collections.Generic.List[string]]::new()

        foreach ($Standard in $script:AllStandards) {
            $Pickers = @($Standard.addedComponent | Where-Object { $_.type -eq 'autoComplete' -and $_.name })
            if ($Pickers.Count -eq 0) { continue }

            $Actual = Remove-CIPPStandardSettingsRawData -Settings (New-SettingsForStandard -Standard $Standard -WithRawData)

            foreach ($Picker in $Pickers) {
                foreach ($Selection in @($Actual.$($Picker.name))) {
                    if (-not $Selection.value -or -not $Selection.label -or -not $Selection.addedFields) {
                        $Broken.Add("$($Standard.name)/$($Picker.name)")
                    }
                }
            }
        }

        $Broken -join ', ' | Should -BeNullOrEmpty
    }

    It 'preserves multi-select cardinality' {
        $Broken = [System.Collections.Generic.List[string]]::new()
        $Checked = 0

        foreach ($Standard in $script:AllStandards) {
            $Multi = @($Standard.addedComponent | Where-Object { $_.type -eq 'autoComplete' -and $_.multiple -and $_.name })
            if ($Multi.Count -eq 0) { continue }

            $Actual = Remove-CIPPStandardSettingsRawData -Settings (New-SettingsForStandard -Standard $Standard -WithRawData)
            foreach ($Picker in $Multi) {
                $Checked++
                if (@($Actual.$($Picker.name)).Count -ne 2) { $Broken.Add("$($Standard.name)/$($Picker.name)") }
            }
        }

        $Checked | Should -BeGreaterThan 0
        $Broken -join ', ' | Should -BeNullOrEmpty
    }

    It 'shrinks the payload wherever a picker exists' {
        $NotShrunk = [System.Collections.Generic.List[string]]::new()

        foreach ($Standard in $script:AllStandards) {
            if (@($Standard.addedComponent | Where-Object { $_.type -eq 'autoComplete' -and $_.name }).Count -eq 0) { continue }

            $WithRaw = New-SettingsForStandard -Standard $Standard -WithRawData
            $Before = (ConvertTo-ComparableJson $WithRaw).Length
            $After = (ConvertTo-ComparableJson (Remove-CIPPStandardSettingsRawData -Settings $WithRaw)).Length

            if ($After -ge $Before) { $NotShrunk.Add($Standard.name) }
        }

        $NotShrunk -join ', ' | Should -BeNullOrEmpty
    }

    It 'leaves standards with no picker completely untouched' {
        $Changed = [System.Collections.Generic.List[string]]::new()
        $Checked = 0

        foreach ($Standard in $script:AllStandards) {
            if (@($Standard.addedComponent | Where-Object { $_.type -eq 'autoComplete' -and $_.name }).Count -gt 0) { continue }
            $Checked++

            $Settings = New-SettingsForStandard -Standard $Standard
            $Actual = Remove-CIPPStandardSettingsRawData -Settings $Settings

            if ((ConvertTo-ComparableJson $Actual) -ne (ConvertTo-ComparableJson $Settings)) {
                $Changed.Add($Standard.name)
            }
        }

        $Checked | Should -BeGreaterThan 50
        $Changed -join ', ' | Should -BeNullOrEmpty
    }
}
