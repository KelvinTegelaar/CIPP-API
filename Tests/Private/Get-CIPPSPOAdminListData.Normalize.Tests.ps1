BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-SPOAdminListInt64.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSPOAdminListData.ps1')
    function Get-SharePointAdminLink { @{ AdminUrl = 'https://x-admin.sharepoint.com' } }
    function New-GraphPOSTRequest {
        [pscustomobject]@{ Row = @(
                [pscustomobject][ordered]@{ Title = 'a'; 'StorageUsed.' = '1,024'; 'NumOfFiles.' = '12'; StorageQuota = '2048' }
                [pscustomobject][ordered]@{ Title = 'b'; StorageUsed = 'abc'; NumOfFiles = ' '; StorageQuota = 0; StorageQuotaBytes = 5 }
                [pscustomobject][ordered]@{ Title = 'c'; StorageQuota = [int64]1099511627776; storageused = '7'; 'StorageUsed.' = '9' }
                [pscustomobject][ordered]@{ Title = 'd' }
            ); NextHref = ''
        }
    }
}

Describe 'Get-CIPPSPOAdminListData row normalisation' {
    It 'copies dotted fields, coerces numbers and derives the quota bytes, moving rewritten fields to the end like Add-Member -Force' {
        Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>' | ConvertTo-Json -Depth 4 -Compress |
            Should -BeExactly '[{"Title":"a","StorageUsed.":"1,024","NumOfFiles.":"12","StorageUsed":1024,"NumOfFiles":12,"StorageQuota":2048,"StorageQuotaBytes":2147483648},{"Title":"b","NumOfFiles":" ","StorageQuota":0,"StorageQuotaBytes":5,"StorageUsed":null},{"Title":"c","StorageUsed.":"9","StorageUsed":7,"StorageQuota":1099511627776,"StorageQuotaBytes":1099511627776},{"Title":"d"}]'
    }
}


Describe 'ConvertTo-SPOAdminListInt64 localization' {
    It 'parses the actual SharePoint storage samples without rounding' {
        ConvertTo-SPOAdminListInt64 -Raw '68 478 349 774' | Should -Be ([int64]68478349774)
        ConvertTo-SPOAdminListInt64 -Raw '68478349774.0000' | Should -Be ([int64]68478349774)
        ConvertTo-SPOAdminListInt64 -Raw '27 487 790 694 400' | Should -Be ([int64]27487790694400)
        ConvertTo-SPOAdminListInt64 -Raw '27487790694400.0' | Should -Be ([int64]27487790694400)
    }

    It 'accepts both common and nonbreaking localized thousands separators' {
        ConvertTo-SPOAdminListInt64 -Raw '1,073,741,824' | Should -Be ([int64]1073741824)
        ConvertTo-SPOAdminListInt64 -Raw "1$([char]0x00A0)073$([char]0x202F)741 824" | Should -Be ([int64]1073741824)
        ConvertTo-SPOAdminListInt64 -Raw '30041' | Should -Be 30041
    }

    It 'rejects units, nonzero fractional quantities and overflow' {
        ConvertTo-SPOAdminListInt64 -Raw '630 717 Mo' | Should -BeNullOrEmpty
        ConvertTo-SPOAdminListInt64 -Raw '1024.5' | Should -BeNullOrEmpty
        ConvertTo-SPOAdminListInt64 -Raw '9223372036854775808' | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPSPOAdminListData SPO byte-valued quota' {
    It 'normalizes real-world RLD storage and quota fields using exact byte units' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ Row = @(
                    [pscustomobject][ordered]@{
                        SiteUrl         = 'https://example.sharepoint.com/sites/A'
                        StorageUsed     = '68 478 349 774'
                        'StorageUsed.'  = '68478349774.0000'
                        StorageQuota    = '27 487 790 694 400'
                        'StorageQuota.' = '27487790694400.0'
                        NumOfFiles      = '30041'
                        'NumOfFiles.'   = '30041'
                    }
                ); NextHref = '' }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows.Count | Should -Be 1
        $Rows[0].StorageUsed | Should -Be ([int64]68478349774)
        $Rows[0].StorageQuota | Should -Be ([int64]27487790694400)
        $Rows[0].StorageQuotaBytes | Should -Be ([int64]27487790694400)
        $Rows[0].NumOfFiles | Should -Be 30041
    }

    It 'does not mistake a 5 GiB byte quota for 5 billion MB' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ Row = @(
                    [pscustomobject][ordered]@{
                        StorageUsed     = '1 073 741 824'
                        'StorageUsed.'  = '1073741824.0'
                        StorageQuota    = '5 368 709 120'
                        'StorageQuota.' = '5368709120.0'
                    }
                ); NextHref = '' }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows[0].StorageQuotaBytes | Should -Be ([int64]5368709120)
    }

    It 'never invents byte units when an explicit dotted quota is unparseable' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ Row = @(
                    [pscustomobject][ordered]@{
                        StorageQuota    = '5 368 709 120'
                        'StorageQuota.' = 'unavailable'
                    }
                ); NextHref = '' }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows[0].StorageQuotaBytes | Should -BeNullOrEmpty
    }
}


Describe 'Get-CIPPSPOAdminListData quota fallback without dotted field' {
    It 'preserves the old MB representation and accepts smaller byte-valued site quotas' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @(
                    [pscustomobject]@{ Title = 'MB 2 GB'; StorageQuota = '2048' }
                    [pscustomobject]@{ Title = 'MB 100 GB'; StorageQuota = '102400' }
                    [pscustomobject]@{ Title = 'Bytes 5 GB'; StorageQuota = '5 368 709 120' }
                    [pscustomobject]@{ Title = 'Bytes 100 GB'; StorageQuota = '107374182400' }
                    [pscustomobject]@{ Title = 'Bytes 25 TB'; StorageQuota = '27487790694400' }
                )
                NextHref = ''
            }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows.Count | Should -Be 5
        $Rows[0].StorageQuotaBytes | Should -Be ([int64](2GB))
        $Rows[1].StorageQuotaBytes | Should -Be ([int64](100GB))
        $Rows[2].StorageQuotaBytes | Should -Be ([int64](5GB))
        $Rows[3].StorageQuotaBytes | Should -Be ([int64](100GB))
        $Rows[4].StorageQuotaBytes | Should -Be ([int64](25TB))
    }

    It 'does not publish a made-up quota for unsupported or ambiguous numeric ranges' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @(
                    [pscustomobject]@{ Title = 'Too small'; StorageQuota = '100' }
                    [pscustomobject]@{ Title = 'Between representations'; StorageQuota = '100000000' }
                    [pscustomobject]@{ Title = 'Too large'; StorageQuota = '54975581388800' }
                )
                NextHref = ''
            }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows.Count | Should -Be 3
        foreach ($Row in $Rows) {
            $Row.StorageQuotaBytes | Should -BeNullOrEmpty
        }
    }

    It 'prefers the explicit dotted byte value even for a small 5 GB quota' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @(
                    [pscustomobject][ordered]@{
                        Title           = 'Small quota'
                        StorageQuota    = '5120'
                        'StorageQuota.' = '5368709120.0000'
                    }
                )
                NextHref = ''
            }
        }
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows[0].StorageQuotaBytes | Should -Be ([int64](5GB))
    }
}

Describe 'Get-CIPPSPOAdminListData sub-1GiB quota fallback' {
    It 'accepts actual 500 MiB App Catalog and 1000 MiB team quotas in both units' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @(
                    [pscustomobject]@{ Title = '500 MiB MB-formatted'; StorageQuota = '500' }
                    [pscustomobject]@{ Title = '500 MiB byte-formatted'; StorageQuota = '524 288 000' }
                    [pscustomobject]@{ Title = '1000 MiB MB-formatted'; StorageQuota = '1000' }
                    [pscustomobject]@{ Title = '1000 MiB byte-formatted'; StorageQuota = '1 048 576 000' }
                )
                NextHref = ''
            }
        }

        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows.Count | Should -Be 4
        $Rows[0].StorageQuotaBytes | Should -Be ([int64](500MB))
        $Rows[1].StorageQuotaBytes | Should -Be ([int64](500MB))
        $Rows[2].StorageQuotaBytes | Should -Be ([int64](1000MB))
        $Rows[3].StorageQuotaBytes | Should -Be ([int64](1000MB))
    }

    It 'prefers dotted byte values for a 500 MiB App Catalog site' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @(
                    [pscustomobject][ordered]@{
                        Title           = 'App Catalog'
                        StorageQuota    = '500'
                        'StorageQuota.' = '524288000.0000'
                    }
                )
                NextHref = ''
            }
        }

        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows[0].StorageQuotaBytes | Should -Be ([int64](500MB))
    }

    It 'still rejects values between the disjoint MB and byte ranges' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{
                Row = @([pscustomobject]@{ StorageQuota = '100000000' })
                NextHref = ''
            }
        }

        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter 'contoso.com' -ViewXml '<View/>')
        $Rows[0].StorageQuotaBytes | Should -BeNullOrEmpty
    }
}
