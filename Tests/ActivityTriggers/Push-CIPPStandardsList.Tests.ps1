BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Standards/Push-CIPPStandardsList.ps1')

    $script:Now = [DateTimeOffset]::UtcNow
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Test-CIPPStandardLicense { $true }
    function Get-CIPPStandards {
        param($TenantFilter, $runManually, $TemplateId)
        foreach ($Policy in 'policy-a', 'policy-b') {
            [pscustomobject]@{
                Tenant     = $TenantFilter
                Standard   = 'IntuneTemplate'
                TemplateId = 'std-1'
                Settings   = [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = $Policy } }
            }
        }
    }
    function New-GraphBulkRequest {
        param($Requests, $tenantid, $NoPaginateIds)
        foreach ($Request in $Requests) {
            $Value = if ($Request.id -eq 'Device') {
                @(
                    [pscustomobject]@{ id = 'dev-1'; lastModifiedDateTime = $script:Now.ToString('o'); displayName = 'Policy A' }
                    [pscustomobject]@{ id = 'dev-2'; lastModifiedDateTime = $script:Now.ToString('o'); displayName = 'Policy B' }
                )
            } else { @() }
            [pscustomobject]@{ id = $Request.id; body = [pscustomobject]@{ value = $Value } }
        }
    }
    function Get-CIPPTenantAlignment {
        [pscustomobject]@{
            ComparisonDetails = @(
                [pscustomobject]@{ StandardName = 'standards.IntuneTemplate.policy-a'; Compliant = $true }
                [pscustomobject]@{ StandardName = 'standards.IntuneTemplate.policy-b'; Compliant = $true }
            )
        }
    }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        $RowKey = if ($Filter -match "RowKey eq '([^']+)'") { $Matches[1] }
        switch ($TableName) {
            'templates' {
                switch -Wildcard ($RowKey) {
                    'policy-*' { [pscustomobject]@{ RowKey = $RowKey; JSON = (@{ Type = 'Device'; Displayname = "Policy $($RowKey[-1].ToString().ToUpper())" } | ConvertTo-Json -Compress) } }
                    'std-1' { [pscustomobject]@{ RowKey = 'std-1'; Timestamp = $script:Now } }
                }
            }
            'IntunePolicyTypeTracking' { $script:Tracking[$RowKey] }
        }
    }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) foreach ($Row in @($Entity)) { $script:Tracking[$Row.RowKey] = [pscustomobject]$Row } }
}

Describe 'Push-CIPPStandardsList standards-template change detection' {
    BeforeEach {
        # Policy type unchanged and both policies compliant, so only the standards-template timestamp decides.
        $script:Tracking = @{
            'Device'                 = [pscustomobject]@{ RowKey = 'Device'; LatestPolicyModified = $script:Now.ToString('o'); LatestPolicyId = 'dev-1'; PolicyCount = 2 }
            'StandardTemplate_std-1' = [pscustomobject]@{ RowKey = 'StandardTemplate_std-1'; CachedTimestamp = $script:Now.AddHours(-1) }
        }
    }

    It 'keeps every Intune policy of an edited standards template' {
        $Result = Push-CIPPStandardsList -Item @{ TenantFilter = 'contoso.test' } 6>$null
        @($Result.Settings.TemplateList.value | Sort-Object) | Should -Be @('policy-a', 'policy-b')
    }

    It 'still records the new standards-template timestamp' {
        $null = Push-CIPPStandardsList -Item @{ TenantFilter = 'contoso.test' } 6>$null
        $script:Tracking['StandardTemplate_std-1'].CachedTimestamp | Should -Be $script:Now
    }
}
