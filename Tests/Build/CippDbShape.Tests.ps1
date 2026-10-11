BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    # The PowerShell implementation CippDbShape replaced, kept as the oracle (with .PSBase: a field named count or keys
    # shadowed the dictionary's own Count/Keys, which stopped the sampling at that field).
    function Get-OracleShape($Items, $Max = 300) {
        $ShapeFields = [ordered]@{}
        $ShapeMaxFields = $Max
        $TypeOf = {
            param($Value)
            if ($null -eq $Value) { return 'null' }
            if ($Value -is [bool]) { return 'boolean' }
            if ($Value -is [datetime] -or $Value -is [DateTimeOffset]) { return 'date' }
            if ($Value -is [string]) { return $(if ($Value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') { 'date' } else { 'string' }) }
            if ($Value.GetType().IsPrimitive -or $Value -is [decimal]) { return 'number' }
            if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) { return 'object' }
            if ($Value -is [System.Collections.IEnumerable]) { return 'array' }
            'string'
        }
        $PropertiesOf = {
            param($Value)
            if ($Value -is [System.Collections.IDictionary]) { foreach ($Key in $Value.Keys) { @{ Name = "$Key"; Value = $Value[$Key] } } }
            elseif ($Value -is [System.Management.Automation.PSCustomObject]) { foreach ($Property in $Value.PSObject.Properties) { @{ Name = $Property.Name; Value = $Property.Value } } }
        }
        $NoteField = {
            param([string]$Name, $Value)
            if ($ShapeFields.PSBase.Count -ge $ShapeMaxFields -and -not $ShapeFields.Contains($Name)) { return }
            $Kind = & $TypeOf $Value
            if (-not $ShapeFields.Contains($Name) -or $ShapeFields[$Name] -eq 'null') { $ShapeFields[$Name] = $Kind }
            $Kind
        }
        foreach ($Item in $Items) {
            foreach ($Property in @(& $PropertiesOf $Item)) {
                $Kind = & $NoteField $Property.Name $Property.Value
                $Inner = if ($Kind -eq 'object') { $Property.Value } elseif ($Kind -eq 'array') { foreach ($First in $Property.Value) { $First; break } }
                if ($null -ne $Inner -and (& $TypeOf $Inner) -eq 'object') {
                    foreach ($Child in @(& $PropertiesOf $Inner)) { $null = & $NoteField "$($Property.Name).$($Child.Name)" $Child.Value }
                }
            }
        }
        ($ShapeFields.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    }
    function Get-Shape($Items, $Max = 300) {
        $Fields = [ordered]@{}
        foreach ($Item in $Items) { [CIPP.CippDbShape]::Note($Fields, $Item, $Max) }
        ($Fields.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    }
}

Describe 'CippDbShape matches the PowerShell shape sampling' {
    It 'records <Name> the same way' -ForEach @(
        @{ Name = 'a Graph record'; Items = @('{"id":"1","accountEnabled":true,"createdDateTime":"2024-01-01T10:00:00Z","lower":"2024-01-01t10:00","dateOnly":"2024-01-01","count":5,"ratio":1.5,"big":12345678901234,"nothing":null,"assignedPlans":[{"service":"exchange","assignedDateTime":"2024-01-01T00:00:00Z"}],"emptyList":[],"tags":["a","b"],"nested":{"inner":{"deep":1},"list":[1,2]},"firstNull":[null,{"x":1}]}' | ConvertFrom-Json) }
        @{ Name = 'PowerShell-built rows'; Items = @([pscustomobject]@{ When = [datetime]::UtcNow; Offset = [DateTimeOffset]::UtcNow; Money = [decimal]2.5; Letter = [char]'x'; Byte = [byte]1; Map = @{ k = 1 }; Ordered = [ordered]@{ z = 'a' }; List = [System.Collections.Generic.List[object]]@(@{ q = 1 }); Wrapped = (Add-Member -InputObject 'abc' -NotePropertyName X -NotePropertyValue 1 -PassThru); Guid = [guid]::NewGuid(); Nested = @(@(1, 2)) }) }
        @{ Name = 'a hashtable row'; Items = @(@{ id = 1; child = @{ a = 'b' }; arr = @([pscustomobject]@{ c = 1 }) }) }
        @{ Name = 'a field that is null first and typed later'; Items = @([pscustomobject]@{ a = $null; b = 'x' }, [pscustomobject]@{ a = 'later'; b = 5 }) }
        @{ Name = 'scalars and nulls among the rows'; Items = @('just a string', 5, [pscustomobject]@{ a = 1 }) }
        @{ Name = 'fields named count and keys'; Items = @([pscustomobject]@{ count = 3; keys = @('a'); after = 'x' }) }
    ) {
        Get-Shape $Items | Should -BeExactly (Get-OracleShape $Items)
    }

    It 'stops at the field cap the same way, including the children of a capped field' {
        $Row = [ordered]@{}
        foreach ($i in 1..12) { $Row["f$i"] = $i }
        $Row['obj'] = [pscustomobject]@{ a = 1; b = 2 }
        $Items = @([pscustomobject]$Row, [pscustomobject]@{ f1 = 'x'; late = [pscustomobject]@{ c = 1 } })
        Get-Shape $Items 10 | Should -BeExactly (Get-OracleShape $Items 10)
    }
}

Describe 'Add-CIPPDbItem shape sampling' {
    It 'keeps sampling fields after one named count' {
        $Fields = [ordered]@{}
        [CIPP.CippDbShape]::Note($Fields, [pscustomobject]@{ count = 3; after = 'x' }, 300)
        @($Fields.PSBase.Keys) | Should -Be @('count', 'after')
    }
}
