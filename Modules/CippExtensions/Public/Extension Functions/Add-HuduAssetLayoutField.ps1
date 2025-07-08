function Add-HuduAssetLayoutField {
    Param(
        $AssetLayoutId,
        $Label = 'Microsoft 365',
        $FieldType = 'RichText',
        $Position = 0,
        $ShowInList = $false
    )

    $M365Field = @{
        position     = $Position
        label        = $Label
        field_type   = $FieldType
        show_in_list = $ShowInList
        required     = $false
        expiration   = $false
    }

    $AssetLayout = Get-HuduAssetLayouts -LayoutId $AssetLayoutId

    if ($AssetLayout.fields.label -contains $Label) {
        return $AssetLayout
    }

    $AssetLayoutFields = [System.Collections.Generic.List[object]]::new()
    $AssetLayoutFields.Add($M365Field)
    foreach ($Field in $AssetLayout.fields) {
        $Field.position++
        $AssetLayoutFields.Add($Field)
    }
    Set-HuduAssetLayout -Id $AssetLayoutId -Fields $AssetLayoutFields
}
