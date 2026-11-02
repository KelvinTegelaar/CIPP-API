function Add-HuduAssetLayoutField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$AssetLayoutId,

        [Parameter(Mandatory = $false)]
        [string]$Label = 'Microsoft 365',

        [Parameter(Mandatory = $false)]
        [string]$FieldType = 'RichText',

        [Parameter(Mandatory = $false)]
        [int]$Position = 0,

        [Parameter(Mandatory = $false)]
        [bool]$ShowInList = $false,

        # The layout as already fetched; it is returned unchanged when the field needs no update
        [Parameter(Mandatory = $false)]
        [object]$AssetLayout
    )

    $DesiredField = @{
        position     = $Position
        label        = $Label
        field_type   = $FieldType
        show_in_list = $ShowInList
        required     = $false
        expiration   = $false
    }

    if (-not $AssetLayout) { $AssetLayout = Get-HuduAssetLayouts -LayoutId $AssetLayoutId -ErrorAction Stop }

    $AssetLayoutFields = [System.Collections.Generic.List[object]]::new()
    $ExistingField = $AssetLayout.fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1
    if ($ExistingField) {
        # An existing field keeps the position the partner gave it; only its type and list visibility are enforced
        if ([string]$ExistingField.field_type -eq $FieldType -and [bool]$ExistingField.show_in_list -eq [bool]$ShowInList) {
            return $AssetLayout
        }
        if ($ExistingField -is [System.Collections.IDictionary]) {
            foreach ($Key in $ExistingField.Keys) { $DesiredField[$Key] = $ExistingField[$Key] }
        } else {
            foreach ($Property in $ExistingField.PSObject.Properties) { $DesiredField[$Property.Name] = $Property.Value }
        }
        $DesiredField.field_type = $FieldType
        $DesiredField.show_in_list = $ShowInList
    }

    $RemainingFields = @($AssetLayout.fields | Where-Object { $_.label -ne $Label } | Sort-Object position)
    $InsertAt = if ($ExistingField) {
        @($RemainingFields | Where-Object { [int]$_.position -lt [int]$ExistingField.position }).Count
    } else {
        [Math]::Min([Math]::Max(0, [int]$Position), $RemainingFields.Count)
    }
    for ($Index = 0; $Index -le $RemainingFields.Count; $Index++) {
        if ($Index -eq $InsertAt) { [void]$AssetLayoutFields.Add($DesiredField) }
        if ($Index -lt $RemainingFields.Count) {
            $Field = $RemainingFields[$Index]
            $LayoutField = @{}
            if ($Field -is [System.Collections.IDictionary]) {
                foreach ($Key in $Field.Keys) { $LayoutField[$Key] = $Field[$Key] }
            } else {
                foreach ($Property in $Field.PSObject.Properties) { $LayoutField[$Property.Name] = $Property.Value }
            }
            [void]$AssetLayoutFields.Add($LayoutField)
        }
    }

    for ($Index = 0; $Index -lt $AssetLayoutFields.Count; $Index++) {
        $AssetLayoutFields[$Index].position = $Index
    }

    $Result = Set-HuduAssetLayout -Id $AssetLayoutId -Fields $AssetLayoutFields -ErrorAction Stop
    return $Result
}
