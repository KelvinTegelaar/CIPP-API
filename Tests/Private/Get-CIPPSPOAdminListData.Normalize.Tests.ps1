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
