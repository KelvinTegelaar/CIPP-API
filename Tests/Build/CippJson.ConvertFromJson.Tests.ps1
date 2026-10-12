BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-Shape($Value) { if ($Value -is [datetime]) { "DateTime $($Value.Kind) $($Value.ToString('o'))" } else { "$($Value.GetType().Name) $Value" } }
}

Describe 'CippJson.ConvertFromJson matches ConvertFrom-Json for string values' {
    It 'reads <Text> the same way' -ForEach @(
        @{ Text = '2025-05-05' }
        @{ Text = '2025-05-05T05:05' }
        @{ Text = '2025-05-05T05:05Z' }
        @{ Text = '2025-05-05T05:05:05' }
        @{ Text = '2025-05-05T05:05:05Z' }
        @{ Text = '2025-05-05T05:05:05.1234567Z' }
        @{ Text = '2025-05-05T05:05:05+08:00' }
        @{ Text = '2025-05-05 05:05:05' }
        @{ Text = '20250505' }
        @{ Text = '/Date(1700000000000)/' }
        @{ Text = '/Date(1700000000000+0800)/' }
        @{ Text = '/Date(-1000)/' }
        @{ Text = '/Date(abc)/' }
        @{ Text = 'CVE-2025-1234' }
        @{ Text = '1 GB' }
    ) {
        $Json = ConvertTo-Json -InputObject @{ v = $Text } -Compress
        Get-Shape ([CIPP.CippJson]::ConvertFromJson($Json)).v | Should -Be (Get-Shape ($Json | ConvertFrom-Json).v)
    }
}

Describe 'CippJson.ReadStringField matches reading the field off ConvertFromJson' {
    It 'reads <Name> the same way' -ForEach @(
        @{ Name = 'an array of records'; Json = '[{"deviceId":"1","deviceName":"PC-1"},{"deviceName":"pc-1 "},{"deviceName":"A, inc"}]' }
        @{ Name = 'a missing and a null value'; Json = '[{"deviceId":"1"},{"deviceName":null},{"deviceName":"x"}]' }
        @{ Name = 'a single record'; Json = '{"deviceId":"1","deviceName":"PC-1"}' }
        @{ Name = 'an empty array'; Json = '[]' }
        @{ Name = 'a differently cased field'; Json = '[{"DeviceName":"PC-1"}]' }
        @{ Name = 'date-only and minute-precision strings'; Json = '[{"deviceName":"2025-05-05"},{"deviceName":"2025-05-05T05:05Z"}]' }
    ) {
        $Expected = foreach ($Value in ([CIPP.CippJson]::ConvertFromJson($Json, [string[]]@('deviceName'))).deviceName) { $Value }
        $Actual = [CIPP.CippJson]::ReadStringField($Json, 'deviceName')
        [object]::ReferenceEquals($Actual, $null) | Should -BeFalse
        ConvertTo-Json -InputObject @($Actual) -Compress | Should -BeExactly (ConvertTo-Json -InputObject @($Expected) -Compress)
    }

    It 'returns null for <Name>, so the caller reads it the long way' -ForEach @(
        @{ Name = 'a value read as a date'; Json = '[{"deviceName":"2025-05-05T05:05:05Z"}]' }
        @{ Name = 'a number'; Json = '[{"deviceName":5}]' }
        @{ Name = 'an object value'; Json = '[{"deviceName":{"a":1}}]' }
        @{ Name = 'a non-object record'; Json = '["PC-1"]' }
        @{ Name = 'a repeated field'; Json = '[{"deviceName":"a","DeviceName":"b"}]' }
    ) {
        [object]::ReferenceEquals([CIPP.CippJson]::ReadStringField($Json, 'deviceName'), $null) | Should -BeTrue
    }
}

Describe 'CippJson.ConvertFromJson returned from a function matches ConvertFrom-Json (Invoke-CIPPRestMethod)' {
    It 'returns the same shape for <Json>' -ForEach @(
        @{ Json = '[]' }
        @{ Json = '[{"id":"1"}]' }
        @{ Json = '[{"id":"1"},{"id":"2"}]' }
        @{ Json = '[1,"two",null]' }
        @{ Json = '[[1,2],[3]]' }
        @{ Json = '{"value":[{"id":"1","createdDateTime":"2025-05-05T05:05:05Z"}],"@odata.nextLink":null}' }
        @{ Json = '"text"' }
        @{ Json = 'null' }
        @{ Json = '{"a":{"b":[]}}' }
    ) {
        function Old($Content) { return $Content | ConvertFrom-Json -Depth 100 }
        function New($Content) { return [CIPP.CippJson]::ConvertFromJson($Content) }
        $Expected = Old $Json
        $Actual = New $Json
        @($Actual).Count | Should -Be @($Expected).Count
        ConvertTo-Json -InputObject $Actual -Depth 10 -Compress | Should -BeExactly (ConvertTo-Json -InputObject $Expected -Depth 10 -Compress)
        if ($null -eq $Expected) { $null -eq $Actual | Should -BeTrue } else { $Actual.GetType().Name | Should -Be $Expected.GetType().Name }
    }
}

Describe 'CippJson.ConvertFromJson records behave like records built with Properties.Add' {
    BeforeAll {
        function ConvertTo-SlowRecord([string]$Json) {
            $Parsed = $Json | ConvertFrom-Json -AsHashtable
            $Record = [pscustomobject]@{}
            foreach ($Key in $Parsed.Keys) { $Record.PSObject.Properties.Add([psnoteproperty]::new($Key, $Parsed[$Key])) }
            $Record
        }
    }

    It 'uses the fast member add on this PowerShell' {
        [CIPP.CippJson].Assembly.GetType('CIPP.PSMembers').GetProperty('FastAddAvailable').GetValue($null) | Should -BeTrue
    }

    It 'is found by a member-access site that already cached a miss for that name' {
        $Name = 'zz' + [guid]::NewGuid().ToString('N')
        function Get-Field($Object, $FieldName) { $Object.$FieldName }
        function Get-Static($Object) { $Object.zzStaticProbe }
        $Empty = [pscustomobject]@{ other = 1 }
        foreach ($i in 1..3) { $null = Get-Field $Empty $Name; $null = Get-Static $Empty }

        Get-Field ([CIPP.CippJson]::ConvertFromJson("{`"$Name`":`"v`"}")) $Name | Should -Be 'v'
        Get-Static ([CIPP.CippJson]::ConvertFromJson('{"zzStaticProbe":"s"}')) | Should -Be 's'
    }

    It 'behaves the same for enumeration, Add-Member, Remove, Get-Member and Select-Object' {
        $Json = '{"id":"1","name":"a","nested":{"x":1}}'
        $Fast = [CIPP.CippJson]::ConvertFromJson($Json)
        $Slow = ConvertTo-SlowRecord $Json
        foreach ($Record in $Fast, $Slow) {
            $Record | Add-Member -NotePropertyName extra -NotePropertyValue 2
            $Record.PSObject.Properties.Remove('name')
        }
        $Fast.PSObject.Properties.Name -join ',' | Should -Be ($Slow.PSObject.Properties.Name -join ',')
        (Get-Member -InputObject $Fast -MemberType NoteProperty).Name -join ',' | Should -Be ((Get-Member -InputObject $Slow -MemberType NoteProperty).Name -join ',')
        ($Fast | Select-Object * | ConvertTo-Json -Compress) | Should -Be ($Slow | Select-Object * | ConvertTo-Json -Compress)
        $Fast -is [pscustomobject] | Should -BeTrue
        $Fast.nested.x | Should -Be 1
    }

    It 'rejects a reserved member name as Properties.Add does' {
        { [CIPP.CippJson]::ConvertFromJson('{"psobject":1}') } | Should -Throw '*reserved*'
    }

    It 'keeps the last of two keys that differ only in case, as Properties.Add does' {
        $Record = [pscustomobject]@{}
        $Record.PSObject.Properties.Add([psnoteproperty]::new('a', 1))
        $Record.PSObject.Properties.Add([psnoteproperty]::new('A', 2))
        ([CIPP.CippJson]::ConvertFromJson('{"a":1,"A":2}') | ConvertTo-Json -Compress) | Should -Be ($Record | ConvertTo-Json -Compress)
    }
}
