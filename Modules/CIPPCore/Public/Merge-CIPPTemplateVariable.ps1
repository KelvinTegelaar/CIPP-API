function Merge-CIPPTemplateVariable {
    <#
    .SYNOPSIS
        Keeps the %variables% of a stored template in a fresh capture of the same policy
    .DESCRIPTION
        A field that holds a variable the capture does not keeps the stored value; every other field takes the
        captured value. Settings are matched by definition id, OMA-URI or id rather than position, and a plain
        list that holds a variable is kept whole. Variables whose setting is gone from the capture are added to
        -Dropped.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Existing,
        $Captured,
        [System.Collections.Generic.HashSet[string]]$Dropped
    )

    $Pattern = '%[A-Za-z0-9_.()-]+%'
    $ExistingJson = ConvertTo-Json -InputObject $Existing -Depth 100 -Compress
    $Result = $Captured

    if ($ExistingJson -notmatch $Pattern) {
        # Nothing to keep
    } elseif ($Existing -is [System.Management.Automation.PSCustomObject] -and $Captured -is [System.Management.Automation.PSCustomObject]) {
        foreach ($Property in $Existing.PSObject.Properties) {
            $CapturedProperty = $Captured.PSObject.Properties[$Property.Name]
            if ($CapturedProperty) {
                $CapturedProperty.Value = Merge-CIPPTemplateVariable -Existing $Property.Value -Captured $CapturedProperty.Value -Dropped $Dropped
            } else {
                foreach ($Token in [regex]::Matches((ConvertTo-Json -InputObject $Property.Value -Depth 100 -Compress), $Pattern)) { $null = $Dropped.Add($Token.Value) }
            }
        }
    } elseif ($Existing -is [System.Collections.IList] -and $Captured -is [System.Collections.IList]) {
        $ExistingByKey = @{}
        foreach ($Item in $Existing) {
            if ($Item -isnot [System.Management.Automation.PSCustomObject]) { continue }
            $Key = $Item.settingInstance.settingDefinitionId ?? $Item.settingDefinitionId ?? $Item.omaUri ?? $Item.'definition@odata.bind' ?? $Item.id
            if ($Key) { $ExistingByKey[[string]$Key] = $Item }
        }
        $IsFlat = $true
        foreach ($Item in $Existing) {
            if ($Item -is [System.Collections.IList]) { $IsFlat = $false }
            if ($Item -is [System.Management.Automation.PSCustomObject]) {
                foreach ($Property in $Item.PSObject.Properties) {
                    if ($Property.Value -is [System.Management.Automation.PSCustomObject] -or $Property.Value -is [System.Collections.IList]) { $IsFlat = $false }
                }
            }
        }

        if ($ExistingByKey.Count -gt 0) {
            $Matched = [System.Collections.Generic.HashSet[string]]::new()
            $Result = @(foreach ($Item in $Captured) {
                    $Key = if ($Item -is [System.Management.Automation.PSCustomObject]) { $Item.settingInstance.settingDefinitionId ?? $Item.settingDefinitionId ?? $Item.omaUri ?? $Item.'definition@odata.bind' ?? $Item.id }
                    if ($Key -and $ExistingByKey.ContainsKey([string]$Key)) {
                        $null = $Matched.Add([string]$Key)
                        , (Merge-CIPPTemplateVariable -Existing $ExistingByKey[[string]$Key] -Captured $Item -Dropped $Dropped)
                    } else {
                        , $Item
                    }
                })
            foreach ($Entry in $ExistingByKey.GetEnumerator()) {
                if ($Matched.Contains($Entry.Key)) { continue }
                foreach ($Token in [regex]::Matches((ConvertTo-Json -InputObject $Entry.Value -Depth 100 -Compress), $Pattern)) { $null = $Dropped.Add($Token.Value) }
            }
        } elseif ($IsFlat) {
            # A list of values (CA users, a collection's entries) has no identity to match on, so it is kept whole.
            $Result = $Existing
        } else {
            $Result = @(for ($Index = 0; $Index -lt $Captured.Count; $Index++) {
                    if ($Index -lt $Existing.Count) {
                        , (Merge-CIPPTemplateVariable -Existing $Existing[$Index] -Captured $Captured[$Index] -Dropped $Dropped)
                    } else {
                        , $Captured[$Index]
                    }
                })
            for ($Index = $Captured.Count; $Index -lt $Existing.Count; $Index++) {
                foreach ($Token in [regex]::Matches((ConvertTo-Json -InputObject $Existing[$Index] -Depth 100 -Compress), $Pattern)) { $null = $Dropped.Add($Token.Value) }
            }
        }
    } elseif ($null -eq $Captured -and $Existing -isnot [string]) {
        # A block the tenant no longer has is not brought back for the variables in it.
        foreach ($Token in [regex]::Matches($ExistingJson, $Pattern)) { $null = $Dropped.Add($Token.Value) }
    } else {
        # Keep the stored value only for a variable the capture does not hold itself: a Windows %token% the
        # tenant sends back unchanged is not one a person added.
        $CapturedJson = ConvertTo-Json -InputObject $Captured -Depth 100 -Compress
        foreach ($Token in [regex]::Matches($ExistingJson, $Pattern)) {
            if (-not $CapturedJson.Contains($Token.Value)) { $Result = $Existing; break }
        }
    }

    if ($Result -is [System.Collections.IList]) { return , $Result }
    return $Result
}
