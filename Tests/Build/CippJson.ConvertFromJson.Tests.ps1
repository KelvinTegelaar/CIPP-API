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
