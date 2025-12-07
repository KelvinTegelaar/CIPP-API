@{
    Path                     = 'CIPPCore.psd1'
    OutputDirectory          = '../../Output'
    VersionedOutputDirectory = $false
    CopyPaths                = @(
        @{
            Source      = 'Public\OrganizationManagementRoles.json'
            Destination = 'Public'
        }
        @{
            Source      = 'Public\PermissionsTranslator.json'
            Destination = 'Public'
        }
        @{
            Source      = 'Public\blank.json'
            Destination = 'Public'
        }
        @{
            Source      = 'Public\AdditionalPermissions.json'
            Destination = 'Public'
        }
        @{
            Source      = 'Public\ConversionTable.csv'
            Destination = 'Public'
        }
        @{
            Source      = 'Public\SAMManifest.json'
            Destination = 'Public'
        }
        @{
            Source      = 'lib\NCrontab.Advanced.dll'
            Destination = 'lib'
        }
    )
    Encoding                 = 'UTF8'
    Prefix                   = $null
    Suffix                   = $null
}
