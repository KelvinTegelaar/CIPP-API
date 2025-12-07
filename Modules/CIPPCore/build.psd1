@{
    Path                     = 'CIPPCore.psd1'
    OutputDirectory          = '../../Output'
    VersionedOutputDirectory = $false
    CopyPaths                = @(
        'Public\OrganizationManagementRoles.json'
        'Public\PermissionsTranslator.json'
        'Public\blank.json'
        'Public\AdditionalPermissions.json'
        'Public\ConversionTable.csv'
        'Public\SAMManifest.json'
        'lib\NCrontab.Advanced.dll'
    )
    Encoding                 = 'UTF8'
    Prefix                   = $null
    Suffix                   = $null
}
