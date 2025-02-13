function Remove-ODataProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object,
        [switch]$SkipRemovingProperties,
        [string[]]$PropertiesToRemove = @(),
        [string[]]$SkipRemoveProperties = @(),
        [switch]$SkipRemoveDefaultProperties,
        [switch]$SkipRemovingChildProperties
    )
    if ($SkipRemovingProperties) {
        return
    }
    $defaultProperties = @(
        'id',
        'createdDateTime',
        'lastModifiedDateTime',
        'supportsScopeTags',
        'modifiedDateTime'
    )
    if (-not $Object) {
        return
    }
    $removeProps = New-Object System.Collections.Generic.List[string]
    if ($PropertiesToRemove) {
        $removeProps.AddRange($PropertiesToRemove)
    }
    if (-not $SkipRemoveDefaultProperties) {
        foreach ($defProp in $defaultProperties) {
            if (-not $removeProps.Contains($defProp)) {
                $removeProps.Add($defProp)
            }
        }
    }
    function Remove-PropertyIfPresent {
        param(
            [Parameter(Mandatory)]
            $psObject,
            [Parameter(Mandatory)]
            [string]$propName
        )
        $propExists = $psObject.PSObject.Properties | Where-Object { $_.Name -eq $propName }
        if ($propExists) {
            $psObject.PSObject.Properties.Remove($propName) | Out-Null
        }
    }

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        foreach ($element in $Object) {
            Remove-ODataProperties -Object $element -SkipRemovingProperties:$SkipRemovingProperties -PropertiesToRemove $PropertiesToRemove -SkipRemoveProperties $SkipRemoveProperties -SkipRemoveDefaultProperties:$SkipRemoveDefaultProperties -SkipRemovingChildProperties:$SkipRemovingChildProperties
        }
        return
    }
    if ($Object -is [PSCustomObject]) {
        $odataProps = $Object.PSObject.Properties | Where-Object {
            $_.Name -like '*@odata*Link' -or
            $_.Name -like '*@odata.context' -or
            $_.Name -like '*@odata.id' -or
            ($_.Name -like '*@odata.type' -and $_.Name -ne '@odata.type')
        }

        foreach ($oProp in $odataProps) {
            if (-not $removeProps.Contains($oProp.Name)) {
                $removeProps.Add($oProp.Name)
            }
        }

        foreach ($propName in $removeProps) {
            if ($SkipRemoveProperties -notcontains $propName) {
                Remove-PropertyIfPresent -psObject $Object -propName $propName
            }
        }

        if (-not $SkipRemovingChildProperties) {
            foreach ($prop in $Object.PSObject.Properties) {
                $val = $prop.Value

                if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    foreach ($child in $val) {

                        if ($child -is [PSCustomObject]) {
                            Remove-ODataProperties -Object $child -SkipRemovingProperties:$SkipRemovingProperties -PropertiesToRemove $PropertiesToRemove -SkipRemoveProperties $SkipRemoveProperties -SkipRemoveDefaultProperties:$SkipRemoveDefaultProperties -SkipRemovingChildProperties:$SkipRemovingChildProperties
                        }
                    }
                }
                # If $val is a single PSCustomObject, recurse into it as well.
                elseif ($val -is [PSCustomObject]) {
                    Remove-ODataProperties -Object $val -SkipRemovingProperties:$SkipRemovingProperties -PropertiesToRemove $PropertiesToRemove -SkipRemoveProperties $SkipRemoveProperties -SkipRemoveDefaultProperties:$SkipRemoveDefaultProperties -SkipRemovingChildProperties:$SkipRemovingChildProperties
                }
            }
        }
    }
}
