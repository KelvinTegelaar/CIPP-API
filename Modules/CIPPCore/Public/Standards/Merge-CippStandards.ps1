function Merge-CippStandards {
    param(
        [Parameter(Mandatory = $true)][object]$Existing,
        [Parameter(Mandatory = $true)][object]$New,
        [Parameter(Mandatory = $true)][string]$StandardName
    )

    # If $Existing or $New is $null/empty, just return the other.
    if (-not $Existing) { return $New }
    if (-not $New) { return $Existing }

    # If the standard name ends with 'Template', we treat them as arrays to merge.
    if ($StandardName -like '*Template') {
        $ExistingIsArray = $Existing -is [System.Collections.IEnumerable] -and -not ($Existing -is [string])
        $NewIsArray = $New -is [System.Collections.IEnumerable] -and -not ($New -is [string])

        # Make sure both are arrays
        if (-not $ExistingIsArray) { $Existing = @($Existing) }
        if (-not $NewIsArray) { $New = @($New) }

        return $Existing + $New
    } else {
        # Single‐value standard: override the old with the new
        return $New
    }
}
