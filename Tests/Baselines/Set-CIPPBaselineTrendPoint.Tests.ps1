BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Set-CIPPBaselineTrendPoint.ps1')

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) $script:Rows }
    function Add-CIPPAzDataTableEntity { param($TableName, $Force, $Entity) $script:Written = @($Entity) }
    $script:Point = { param($Key) @($script:Written).Where({ $_.PartitionKey -eq $Key })[0] }
}

Describe 'Set-CIPPBaselineTrendPoint' {
    It 'buckets statuses case-insensitively and groups tenants and standards case-insensitively' {
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = 'Contoso.com'; StandardName = 'Std#1'; Status = 'Compliant' }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; StandardName = 'std#1'; Status = 'accepted' }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; StandardName = 'Std#2'; Status = 'Partially Accepted' }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; StandardName = 'Std#2'; Status = 'drift' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; StandardName = 'Std#1'; Status = 'denied - report only' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; StandardName = 'Std#1'; Status = 'Denied-NoSpace' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; StandardName = ''; Status = 'No Data' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; StandardName = $null; Status = 'Skipped - No License' }
        )
        Set-CIPPBaselineTrendPoint

        @($script:Written).Count | Should -Be 5
        $Fleet = & $script:Point 'fleet'
        $Fleet.Total | Should -Be 8
        $Fleet.Applicable | Should -Be 6
        $Fleet.Compliant | Should -Be 1
        $Fleet.Accepted | Should -Be 1
        $Fleet.Drift | Should -Be 2
        $Fleet.Denied | Should -Be 1
        $Fleet.LicenseMissing | Should -Be 1
        $Fleet.Aligned | Should -Be 33
        $Fleet.Verified | Should -Be 17

        (& $script:Point 'tenant_Contoso.com').Total | Should -Be 4
        $Standard = & $script:Point 'standard_Std~1'
        $Standard.Total | Should -Be 4
        $Standard.Aligned | Should -Be 50
        (& $script:Point 'standard_Std~2').Drift | Should -Be 2
    }

    It 'scores a bucket with nothing applicable as 0' {
        $script:Rows = @([pscustomobject]@{ PartitionKey = 'contoso.com'; StandardName = 'Std#1'; Status = 'No Data' })
        Set-CIPPBaselineTrendPoint

        $Fleet = & $script:Point 'fleet'
        $Fleet.Applicable | Should -Be 0
        $Fleet.Aligned | Should -Be 0
        $Fleet.RowKey | Should -Be (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    }
}
