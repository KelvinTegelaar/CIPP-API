function Merge-CippStandards {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Existing,
        [Parameter(Mandatory = $true)]
        [object]$New
    )

    if (-not $Existing) {
        return $New
    }
    $ExistingIsArray = ($Existing -is [System.Collections.IEnumerable] -and -not ($Existing -is [string]))
    $NewIsArray = ($New -is [System.Collections.IEnumerable] -and -not ($New -is [string]))

    if (-not $ExistingIsArray) {
        $Existing = @($Existing)
    }
    if (-not $NewIsArray) {
        $New = @($New)
    }
    return $Existing + $New
}
