@{
    Path                     = 'CIPPCore.psd1'
    OutputDirectory          = '../../Output'
    VersionedOutputDirectory = $false
    CopyPaths                = @(
        'lib',
        'Public/Tests/'
    )
    ExcludePaths             = @(
        'Public/Tests'
    )
    Encoding                 = 'UTF8'
    Prefix                   = $null
    Suffix                   = $null
}
