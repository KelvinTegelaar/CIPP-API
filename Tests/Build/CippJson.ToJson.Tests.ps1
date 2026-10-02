BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-Expected($Value) { ConvertTo-Json -InputObject $Value -Depth 100 -Compress }
}

Describe 'CippJson.ToJson matches ConvertTo-Json -Compress' {
    It 'serialises <Name> identically' -ForEach @(
        @{ Name = 'a ConvertFrom-Json record'; Value = ('{"a":"x\"y\\z\u00e9\u2028<>&''\t","b":1,"c":1.5,"d":true,"e":null,"f":"2025-03-24T22:46:42+08:00","g":"2025-03-24T22:46:42Z","h":[1,"two",{"i":[]}],"j":{},"k":-9223372036854775808,"l":9223372036854775807,"m":1e300}' | ConvertFrom-Json) }
        @{ Name = 'a PowerShell-built row'; Value = [pscustomobject][ordered]@{ I = [int]7; D = [double]1.0; M = [decimal]2.50; U = [datetime]::new(2025, 3, 24, 1, 2, 3, [DateTimeKind]::Utc); L = [datetime]::new(2025, 3, 24, 1, 2, 3, [DateTimeKind]::Local); N = [datetime]::new(2025, 3, 24, 1, 2, 3); G = [guid]'4ab9d8a8-0e71-4488-8d5b-d30260561fa6'; E = [DayOfWeek]::Monday; A = @(); H = @{ k = @(1, 2) }; S = ''; Z = $null } }
        @{ Name = 'an ordered dictionary'; Value = [ordered]@{ b = 1; a = [ordered]@{ c = 'x'; d = @($true, $null) } } }
        @{ Name = 'a generic list'; Value = [System.Collections.Generic.List[object]]@('a', 1, @{ x = 1 }) }
        @{ Name = 'an empty object'; Value = [pscustomobject]@{} }
        @{ Name = 'Get-Date output'; Value = Get-Date }
        @{ Name = 'noted strings and dates inside a row'; Value = [pscustomobject]@{ When = Get-Date; S = (Add-Member -InputObject 'abc' -NotePropertyName X -NotePropertyValue 1 -PassThru) } }
        @{ Name = 'a row from Select-Object over parsed JSON'; Value = ('{"a":"x","b":[1,"y"],"c":{"d":2}}' | ConvertFrom-Json | Select-Object a, b, c) }
        @{ Name = 'an empty foreach result held in a row'; Value = & { $Empty = foreach ($x in @()) { $x }; [pscustomobject]@{ G = $Empty; N = 1 } } }
    ) {
        [CIPP.CippJson]::ToJson($Value, 100) | Should -BeExactly (Get-Expected $Value)
    }

    It 'returns null for <Name>, so the caller falls back to ConvertTo-Json' -ForEach @(
        @{ Name = 'a noted hashtable inside a row'; Value = [pscustomobject]@{ H = (Add-Member -InputObject ([psobject]::new(@{ k = 1 })) -NotePropertyName X -NotePropertyValue 1 -PassThru) } }
        @{ Name = 'a noted number inside a row'; Value = [pscustomobject]@{ N = (Add-Member -InputObject ([psobject]::new([int64]5)) -NotePropertyName X -NotePropertyValue 1 -PassThru) } }
        @{ Name = 'a noted list inside a row'; Value = [pscustomobject]@{ L = (Add-Member -InputObject ([psobject]::new([object[]]@(1, 2))) -NotePropertyName X -NotePropertyValue 1 -PassThru) } }
        @{ Name = 'a DateTimeOffset'; Value = [DateTimeOffset]::UtcNow }
        @{ Name = 'an arbitrary .NET object'; Value = [version]'1.2.3' }
        @{ Name = 'nesting deeper than the depth'; Value = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{ c = 1 } } }; Depth = 1 }
    ) {
        [CIPP.CippJson]::ToJson($Value, $(if ($Depth) { $Depth } else { 100 })) | Should -BeNullOrEmpty
    }
}
