function Add-HuduAssetLayoutM365Field {
    Param(
        $AssetLayoutId
    )

    $M365Field = @{
        position     = 0
        label        = 'Microsoft 365'
        field_type   = 'RichText'
        show_in_list = $false
        required     = $false
        expiration   = $false
    }

    $AssetLayout = Get-HuduAssetLayouts -LayoutId $AssetLayoutId

    if ($AssetLayout.fields.label -contains 'Microsoft 365') {
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
