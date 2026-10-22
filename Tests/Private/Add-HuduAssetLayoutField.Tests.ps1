BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Extension Functions/Add-HuduAssetLayoutField.ps1"
    function Get-HuduAssetLayouts { param($LayoutId) $script:Layout }
    function Set-HuduAssetLayout {
        param($Id, $Fields)
        foreach ($field in $Fields) { $field.Remove('required') }
        $script:SentFields = $Fields
        $script:Layout.fields = @($Fields | ForEach-Object { [PSCustomObject]$_ })
    }
}
Describe 'Hudu layout field normalization' {
    It 'copies object and dictionary fields and inserts at the requested position' {
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'Serial'; position = 0; required = $false; field_type = 'Text' }
            @{ id = 2; label = 'Notes'; position = 1; required = $false; field_type = 'RichText' }
        ) }
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Password' -FieldType 'Password' -Position 1
        $script:SentFields.Count | Should -Be 3
        $script:SentFields[0].id | Should -Be 1
        $script:SentFields[1].field_type | Should -Be 'Password'
        $script:SentFields[2].position | Should -Be 2
        $script:Layout.fields[0].position | Should -Be 0
        $script:Layout.fields[1].position | Should -Be 1
    }
    It 'does not update a layout when field type and position already match' {
        $script:SentFields = $null
        $script:Layout = @{ fields = @([PSCustomObject]@{ label = 'LAPS Password'; position = 0; field_type = 'Password'; show_in_list = $false }) }
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Password' -FieldType Password -Position 0
        $script:SentFields | Should -BeNullOrEmpty
    }

    It 'preserves identifiers and custom properties when the target field is a dictionary' {
        $script:Layout = @{ fields = @(
            @{ id = 10; label = 'LAPS Account'; position = 1; field_type = 'Text'; show_in_list = $true; custom_option = 'preserve-me' }
            @{ id = 11; label = 'LAPS Password'; position = 0; field_type = 'Password'; show_in_list = $false }
        ) }

        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Account' -FieldType 'Email' -Position 0

        $Account = $script:SentFields | Where-Object { $_.label -eq 'LAPS Account' }
        $Account.id | Should -Be 10
        $Account.custom_option | Should -Be 'preserve-me'
        $Account.field_type | Should -Be 'Email'
    }

    It 'fixes the type of an existing field without moving it' {
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'LAPS Password'; position = 0; field_type = 'Password'; show_in_list = $false }
            [PSCustomObject]@{ id = 2; label = 'LAPS Account'; position = 1; field_type = 'Text'; show_in_list = $false }
        ) }
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Account' -FieldType Email -Position 0
        $script:SentFields[0].label | Should -Be 'LAPS Password'
        $script:SentFields[1].label | Should -Be 'LAPS Account'
        $script:SentFields[1].field_type | Should -Be 'Email'
    }

    It 'adds missing CIPP fields in order above the existing fields on first sync' {
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'Serial'; position = 0; field_type = 'Text'; show_in_list = $false }
            [PSCustomObject]@{ id = 2; label = 'Warranty'; position = 1; field_type = 'Date'; show_in_list = $false }
        ) }
        foreach ($Field in @(
                @{ Label = 'LAPS Account'; FieldType = 'Email'; Position = 0 }
                @{ Label = 'LAPS Password'; FieldType = 'Password'; Position = 1 }
                @{ Label = 'LAPS Backup Date'; FieldType = 'Text'; Position = 2 }
                @{ Label = 'Microsoft 365'; FieldType = 'RichText'; Position = 3 }
            )) { Add-HuduAssetLayoutField -AssetLayoutId 10 @Field }
        ($script:Layout.fields | Sort-Object position).label | Should -Be @('LAPS Account', 'LAPS Password', 'LAPS Backup Date', 'Microsoft 365', 'Serial', 'Warranty')
    }

    It 'leaves CIPP fields where the partner moved them' {
        $script:SentFields = $null
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'Serial'; position = 0; field_type = 'Text'; show_in_list = $false }
            [PSCustomObject]@{ id = 2; label = 'Warranty'; position = 1; field_type = 'Date'; show_in_list = $false }
            [PSCustomObject]@{ id = 3; label = 'Microsoft 365'; position = 2; field_type = 'RichText'; show_in_list = $false }
            [PSCustomObject]@{ id = 4; label = 'LAPS Password'; position = 3; field_type = 'Password'; show_in_list = $false }
        ) }
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'Microsoft 365' -FieldType RichText -Position 0
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Password' -FieldType Password -Position 1
        $script:SentFields | Should -BeNullOrEmpty
    }

    It 'keeps the relative order when an existing field sits between non-contiguous positions' {
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'Serial'; position = 0; field_type = 'Text'; show_in_list = $false }
            [PSCustomObject]@{ id = 2; label = 'LAPS Account'; position = 4; field_type = 'Text'; show_in_list = $false }
            [PSCustomObject]@{ id = 3; label = 'Site Notes'; position = 9; field_type = 'Text'; show_in_list = $false }
        ) }
        Add-HuduAssetLayoutField -AssetLayoutId 10 -Label 'LAPS Account' -FieldType Email -Position 0
        $script:SentFields.label | Should -Be @('Serial', 'LAPS Account', 'Site Notes')
    }

    It 'adds credential fields, fixes types in place, preserves custom layout data, and is idempotent' {
        $script:Layout = @{ fields = @(
            [PSCustomObject]@{ id = 1; label = 'LAPS Password'; position = 0; field_type = 'Password'; show_in_list = $false }
            [PSCustomObject]@{ id = 2; label = 'LAPS Account'; position = 1; field_type = 'Text'; show_in_list = $false }
            [PSCustomObject]@{ id = 3; label = 'BitLocker Keys'; position = 2; field_type = 'RichText'; show_in_list = $false }
            [PSCustomObject]@{ id = 4; label = 'Site Notes'; position = 3; field_type = 'Text'; show_in_list = $true; custom_option = 'preserve-me' }
        ) }

        $DesiredFields = @(
            @{ Label = 'LAPS Account'; FieldType = 'Email'; Position = 0 }
            @{ Label = 'LAPS Password'; FieldType = 'Password'; Position = 1 }
            @{ Label = 'LAPS Backup Date'; FieldType = 'Text'; Position = 2 }
            @{ Label = 'BitLocker OS Drive 1 Key ID'; FieldType = 'Text'; Position = 5 }
            @{ Label = 'BitLocker OS Drive 1 Recovery Key'; FieldType = 'Password'; Position = 6 }
            @{ Label = 'BitLocker Fixed Data Drive 1 Key ID'; FieldType = 'Text'; Position = 7 }
            @{ Label = 'BitLocker Fixed Data Drive 1 Recovery Key'; FieldType = 'Password'; Position = 8 }
        )
        foreach ($Field in $DesiredFields) { Add-HuduAssetLayoutField -AssetLayoutId 10 @Field }

        $script:Layout.fields[0].label | Should -Be 'LAPS Password'
        $script:Layout.fields[1].label | Should -Be 'LAPS Account'
        $script:Layout.fields[1].field_type | Should -Be 'Email'
        $script:Layout.fields[2].label | Should -Be 'LAPS Backup Date'
        $script:Layout.fields.label | Should -Contain 'BitLocker OS Drive 1 Key ID'
        $script:Layout.fields.label | Should -Contain 'BitLocker OS Drive 1 Recovery Key'
        $script:Layout.fields.label | Should -Contain 'BitLocker Fixed Data Drive 1 Key ID'
        $script:Layout.fields.label | Should -Contain 'BitLocker Fixed Data Drive 1 Recovery Key'
        ($script:Layout.fields | Where-Object label -eq 'BitLocker OS Drive 1 Key ID').position | Should -Be 5
        ($script:Layout.fields | Where-Object label -eq 'BitLocker OS Drive 1 Recovery Key').position | Should -Be 6
        ($script:Layout.fields | Where-Object label -eq 'BitLocker Fixed Data Drive 1 Key ID').position | Should -Be 7
        ($script:Layout.fields | Where-Object label -eq 'BitLocker Fixed Data Drive 1 Recovery Key').position | Should -Be 8
        ($script:Layout.fields | Where-Object label -eq 'BitLocker Keys').id | Should -Be 3
        ($script:Layout.fields | Where-Object label -eq 'Site Notes').custom_option | Should -Be 'preserve-me'

        $script:SentFields = $null
        foreach ($Field in $DesiredFields) { Add-HuduAssetLayoutField -AssetLayoutId 10 @Field }
        $script:SentFields | Should -BeNullOrEmpty
    }
}
