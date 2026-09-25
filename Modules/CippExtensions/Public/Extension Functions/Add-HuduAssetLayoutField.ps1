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
        [bool]$ShowInList = $false
    )

    $DesiredField = @{
        position     = $Position
        label        = $Label
        field_type   = $FieldType
        show_in_list = $ShowInList
        required     = $false
        expiration   = $false
    }

    $AssetLayout = Get-HuduAssetLayouts -LayoutId $AssetLayoutId -ErrorAction Stop

    $AssetLayoutFields = [System.Collections.Generic.List[object]]::new()
    $ExistingField = $AssetLayout.fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1
    if ($ExistingField) {
        if ($ExistingField -is [System.Collections.IDictionary]) {
            foreach ($Key in $ExistingField.Keys) { $DesiredField[$Key] = $ExistingField[$Key] }
        } else {
            foreach ($Property in $ExistingField.PSObject.Properties) { $DesiredField[$Property.Name] = $Property.Value }
        }
        $DesiredField.position = $Position
        $DesiredField.field_type = $FieldType
        $DesiredField.show_in_list = $ShowInList
    }

    $RemainingFields = @($AssetLayout.fields | Where-Object { $_.label -ne $Label } | Sort-Object position)
    $InsertAt = [Math]::Min([Math]::Max(0, [int]$Position), $RemainingFields.Count)
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

    if ($ExistingField -and [int]$ExistingField.position -eq $InsertAt -and
        [string]$ExistingField.field_type -eq $FieldType -and
        [bool]$ExistingField.show_in_list -eq [bool]$ShowInList) {
        return $AssetLayout
    }

    $Result = Set-HuduAssetLayout -Id $AssetLayoutId -Fields $AssetLayoutFields -ErrorAction Stop
    return $Result
}
