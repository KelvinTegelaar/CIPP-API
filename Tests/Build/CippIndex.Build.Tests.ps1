BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $NullKey = [string][char]0

    # The PowerShell builder CippIndex.Build replaced in Invoke-NinjaOneTenantSync
    function Build-Reference($Items, [scriptblock]$KeysOf) {
        $Index = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Item in $Items) {
            $Keys = & $KeysOf $Item
            if ($null -eq $Keys) { $Keys = , $null }
            foreach ($Key in $Keys) {
                $K = if ($null -eq $Key) { $NullKey } else { [string]$Key }
                $L = $null
                if (-not $Index.TryGetValue($K, [ref]$L)) { $L = [System.Collections.Generic.List[object]]::new(); $Index[$K] = $L }
                if ($L.Count -eq 0 -or -not [object]::ReferenceEquals($L[$L.Count - 1], $Item)) { $L.Add($Item) }
            }
        }
        , $Index
    }
    function Build-Sharp($Items, [scriptblock]$KeysOf) {
        $List = [System.Collections.Generic.List[object]]::new()
        $KeySets = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Items) { $List.Add($Item); $KeySets.Add((& $KeysOf $Item)) }
        , [CIPP.CippIndex]::Build($List.ToArray(), $KeySets.ToArray(), $NullKey)
    }
    function Get-Shape($Index) {
        @(foreach ($K in $Index.Keys) { "$([int][char]($K + ' ')[0])|$K=" + (@($Index[$K] | ForEach-Object { [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_) }) -join ',') }) -join "`n"
    }

    $script:Users = @(1..4 | ForEach-Object { [pscustomobject]@{ id = "U$_"; upn = "user$_@Contoso.com" } })
    $script:Groups = @(
        [pscustomobject]@{ id = 'g1'; members = @($Users[0], $Users[1], [pscustomobject]@{ id = 'd1'; deviceId = 'DEV-1' }) }
        [pscustomobject]@{ id = 'g2'; members = @($Users[1]) }
        [pscustomobject]@{ id = 'g3'; members = @() }
        [pscustomobject]@{ id = 'G1'; members = @($Users[1], $Users[1]) }
    )
    $script:Holders = @(
        [pscustomobject]@{ v = @() }
        [pscustomobject]@{ v = @('k1') }
        [pscustomobject]@{ v = @('k1', 'k2') }
        [pscustomobject]@{ v = $null }
        [pscustomobject]@{ v = @(, @('n1', 'n2')) }
    )
    $script:Mixed = @(
        [pscustomobject]@{ n = 1.5; when = [datetime]::new(2026, 10, 1, 13, 5, 0); tags = @('A', 'a', $null) }
        [pscustomobject]@{ n = 2; when = $null; tags = 'solo' }
    )
}

Describe 'CippIndex.Build matches the PowerShell index builder' {
    It 'indexes <Name> identically' -ForEach @(
        @{ Name = 'one scalar key per item'; Items = { $Users }; KeysOf = { param($U) $U.id } }
        @{ Name = 'case-insensitive keys that collide'; Items = { $Groups }; KeysOf = { param($G) $G.id } }
        @{ Name = 'member ids across groups, with repeats'; Items = { $Groups }; KeysOf = { param($G) $G.members.id } }
        @{ Name = 'device ids that are mostly null'; Items = { $Groups }; KeysOf = { param($G) $G.members.deviceId } }
        @{ Name = 'two keys per item'; Items = { $Users }; KeysOf = { param($U) $U.id, $U.upn } }
        @{ Name = 'no output, so a null key'; Items = { $Users }; KeysOf = { } }
        @{ Name = 'an empty collection, so no key'; Items = { $Users }; KeysOf = { , @() } }
        @{ Name = 'a keyset returned as one array'; Items = { $Groups }; KeysOf = { param($G) , @($G.members.id) } }
        @{ Name = 'numbers and dates as keys'; Items = { $Mixed }; KeysOf = { param($M) $M.n, $M.when } }
        @{ Name = 'nested key lists with nulls'; Items = { $Mixed }; KeysOf = { param($M) $M.tags } }
        @{ Name = 'a whole list as one pseudo-item'; Items = { , $Users }; KeysOf = { param($All) $All.id } }
        @{ Name = 'a null item among items'; Items = { @($Users[0], $null, $Users[1]) }; KeysOf = { param($U) $U.id } }
        @{ Name = 'no items'; Items = { @() }; KeysOf = { param($U) $U.id } }
    ) {
        $In = & $Items
        Get-Shape (Build-Sharp $In $KeysOf) | Should -BeExactly (Get-Shape (Build-Reference $In $KeysOf))
    }

    It 'returns a case-insensitive Dictionary[string, List[object]] that the sync can extend' {
        $Index = Build-Sharp $Users { param($U) $U.id }
        $Index -is [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]] | Should -BeTrue
        $Index.ContainsKey('u1') | Should -BeTrue
        $Index['U1'].Add('extra')
        $Index['u1'].Count | Should -Be 2
    }

    It 'indexes <Name> identically when the sync computes keys inline' -ForEach @(
        @{ Name = 'member ids'; Items = { $Groups }; KeysOf = { param($G) $G.members.id }; Inline = { param($In) , @(foreach ($G in $In) { , ($($G.members.id) ?? $null) }) } }
        @{ Name = 'mostly-null device ids'; Items = { $Groups }; KeysOf = { param($G) $G.members.deviceId }; Inline = { param($In) , @(foreach ($G in $In) { , ($($G.members.deviceId) ?? $null) }) } }
        @{ Name = 'a property holding an empty array'; Items = { $Holders }; KeysOf = { param($H) $H.v }; Inline = { param($In) , @(foreach ($H in $In) { , ($($H.v) ?? $null) }) } }
        @{ Name = 'two keys per item'; Items = { $Users }; KeysOf = { param($U) $U.id, $U.upn }; Inline = { param($In) , @(foreach ($U in $In) { , ($($U.id, $U.upn) ?? $null) }) } }
        @{ Name = 'a single item that is not an array'; Items = { $Users[0] }; KeysOf = { param($U) $U.id }; Inline = { param($In) , @(foreach ($U in $In) { , ($($U.id) ?? $null) }) } }
        @{ Name = 'null items'; Items = { $null }; KeysOf = { param($U) $U.id }; Inline = { param($In) , @(foreach ($U in $In) { , ($($U.id) ?? $null) }) } }
    ) {
        $In = & $Items
        Get-Shape ([CIPP.CippIndex]::Build($In, (& $Inline $In))) | Should -BeExactly (Get-Shape (Build-Reference $In $KeysOf))
    }

    It 'Find, Has and AddItem behave like the scriptblocks they replace' {
        $Find = { param($Index, $Key) $L = $null; if ($Index.TryGetValue($(if ($null -eq $Key) { $NullKey } else { [string]$Key }), [ref]$L)) { $L } }
        $Has = { param($Index, $Key) $Index.ContainsKey($(if ($null -eq $Key) { $NullKey } else { [string]$Key })) }
        $Old = Build-Reference $Groups { param($G) $G.members.deviceId }
        $New = Build-Sharp $Groups { param($G) $G.members.deviceId }
        $Old2 = Build-Reference $Groups { param($G) $G.members.id }
        $New2 = Build-Sharp $Groups { param($G) $G.members.id }
        foreach ($Key in @($null, 'DEV-1', 'dev-1', 'missing', 'U1', 'u2')) {
            $A = & $Find $Old $Key; $B = $New.Find($Key)
            Get-Shape @{ k = @($A) } | Should -BeExactly (Get-Shape @{ k = @($B) })
            ($A -is [array]) | Should -Be ($B -is [array])
            $New.Has($Key) | Should -Be (& $Has $Old $Key)
            Get-Shape @{ k = @(& $Find $Old2 $Key) } | Should -BeExactly (Get-Shape @{ k = @($New2.Find($Key)) })
        }
        $Extra = [pscustomobject]@{ id = 'x' }
        $New.AddItem('DEV-1', $Extra); $New.AddItem('dev-1', $Extra); $New.AddItem($null, $Extra)
        @($New.Find('DEV-1'))[-1] | Should -Be $Extra
        @($New.Find('DEV-1')).Count | Should -Be 2
        @($New.Find($null))[-1] | Should -Be $Extra
    }
}
