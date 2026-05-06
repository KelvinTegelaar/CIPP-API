function Find-CIPPFuzzyPolicyMatch {
    <#
    .SYNOPSIS
        Finds the best matching policy from a collection using exact or fuzzy name matching.
    .DESCRIPTION
        First attempts an exact name match. If no exact match is found and MaxDistance is greater
        than zero, attempts a fuzzy match using Levenshtein distance. Optionally filters candidates
        by @odata.type or Catalog templateId to prevent replacing a policy of a different sub-type.
        When multiple candidates fall within the threshold, the one with the lowest distance
        (tie-broken by most recent lastModifiedDateTime) is returned and a warning is logged.
    .PARAMETER DisplayName
        The display name from the template to match against existing policies.
    .PARAMETER ExistingPolicies
        The collection of existing policies returned from a Graph API GET request.
    .PARAMETER NameProperty
        The property on each policy object that holds its display name. Defaults to 'displayName'.
        Use 'name' for Catalog (configurationPolicies) policies.
    .PARAMETER MaxDistance
        Maximum allowed Levenshtein edit distance for a fuzzy match. 0 means exact match only
        (the default, preserving pre-existing behaviour).
    .PARAMETER ODataType
        Optional. When provided, only candidates whose @odata.type matches this value are
        considered for fuzzy matching. This prevents a similarly-named policy of a different
        sub-type from being replaced inadvertently.
    .PARAMETER TemplateId
        Optional. For Catalog policies, the templateReference.templateId from the template JSON.
        When provided, only candidates whose templateReference.templateId matches are considered.
    .EXAMPLE
        $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'My Policy v4.0' -ExistingPolicies $existing -MaxDistance 3
        if ($result) { $ExistingID = $result.Policy }
    .EXAMPLE
        $result = Find-CIPPFuzzyPolicyMatch -DisplayName 'Device Config' -ExistingPolicies $existing `
            -MaxDistance 2 -ODataType '#microsoft.graph.windows10GeneralConfiguration'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$ExistingPolicies,

        [Parameter(Mandatory = $false)]
        [string]$NameProperty = 'displayName',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10)]
        [int]$MaxDistance = 0,

        [Parameter(Mandatory = $false)]
        [string]$ODataType,

        [Parameter(Mandatory = $false)]
        [string]$TemplateId
    )

    # Guard: empty collection
    if (-not $ExistingPolicies -or $ExistingPolicies.Count -eq 0) {
        return $null
    }

    # --- 1. Exact match (always attempted first, regardless of MaxDistance) ---
    $exactMatch = $ExistingPolicies | Where-Object { $_.$NameProperty -eq $DisplayName } |
        Sort-Object -Property lastModifiedDateTime -Descending |
        Select-Object -First 1

    if ($exactMatch) {
        return [PSCustomObject]@{
            Policy       = $exactMatch
            MatchType    = 'exact'
            Distance     = 0
            OriginalName = $exactMatch.$NameProperty
        }
    }

    # --- 2. Fuzzy matching (only when enabled) ---
    if ($MaxDistance -le 0) {
        return $null
    }

    # Build candidate list, applying sub-type filters when requested
    $candidates = $ExistingPolicies

    if ($ODataType) {
        $candidates = $candidates | Where-Object { $_.'@odata.type' -eq $ODataType }
    }

    if ($TemplateId) {
        $candidates = $candidates | Where-Object { $_.templateReference.templateId -eq $TemplateId }
    }

    if (-not $candidates -or @($candidates).Count -eq 0) {
        return $null
    }

    # Score every candidate
    $scored = foreach ($policy in $candidates) {
        $policyName = $policy.$NameProperty
        if ([string]::IsNullOrEmpty($policyName)) { continue }

        $dist = Get-CIPPLevenshteinDistance -Source $DisplayName -Target $policyName
        [PSCustomObject]@{
            Policy       = $policy
            Distance     = $dist
            OriginalName = $policyName
            LastModified = $policy.lastModifiedDateTime
        }
    }

    # Keep only matches within the allowed threshold
    $withinThreshold = @($scored | Where-Object { $_.Distance -le $MaxDistance })

    if ($withinThreshold.Count -eq 0) {
        return $null
    }

    # Sort: lowest distance first; for equal distances prefer most recently modified
    $sorted = $withinThreshold | Sort-Object -Property @{Expression = 'Distance'; Ascending = $true }, @{Expression = 'LastModified'; Descending = $true }

    $best = $sorted | Select-Object -First 1

    # Warn when multiple candidates fall within the threshold
    if ($withinThreshold.Count -gt 1) {
        $allNames = ($sorted | ForEach-Object { "'$($_.OriginalName)' (dist=$($_.Distance))" }) -join ', '
        Write-Information "Find-CIPPFuzzyPolicyMatch: Multiple candidates within distance $MaxDistance for '$DisplayName': $allNames. Selecting '$($best.OriginalName)'."
    }

    return [PSCustomObject]@{
        Policy       = $best.Policy
        MatchType    = 'fuzzy'
        Distance     = $best.Distance
        OriginalName = $best.OriginalName
    }
}
