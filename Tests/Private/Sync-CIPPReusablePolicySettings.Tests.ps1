BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGETRequest { param($Uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Compare-CIPPIntuneObject { param($ReferenceObject, $DifferenceObject, $compareType) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Sync-CIPPReusablePolicySettings.ps1')

    $script:TemplateInfo = [pscustomobject]@{
        RawJSON          = '{"ref":"src-1"}'
        ReusableSettings = @([pscustomobject]@{ templateId = 'tpl-1'; sourceId = 'src-1'; displayName = 'Shared setting' })
    }
}

Describe 'Sync-CIPPReusablePolicySettings' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-1'; JSON = (@{ RawJSON = '{"displayName":"Shared setting"}' } | ConvertTo-Json) } }
        Mock Compare-CIPPIntuneObject { 'different' }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ id = 'created-id' } }
    }

    It '-ReadOnly maps an existing setting that differs without updating it' {
        Mock New-GraphGETRequest { [pscustomobject]@{ id = 'tenant-id'; displayName = 'Shared setting' } }
        $Result = Sync-CIPPReusablePolicySettings -TemplateInfo $script:TemplateInfo -Tenant 'contoso.onmicrosoft.com' -ReadOnly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result.RawJSON | Should -Be '{"ref":"tenant-id"}'
    }

    It '-ReadOnly does not create a missing setting' {
        Mock New-GraphGETRequest { }
        $Result = Sync-CIPPReusablePolicySettings -TemplateInfo $script:TemplateInfo -Tenant 'contoso.onmicrosoft.com' -ReadOnly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result.RawJSON | Should -Be '{"ref":"src-1"}'
    }

    It 'creates a missing setting without -ReadOnly' {
        Mock New-GraphGETRequest { }
        $Result = Sync-CIPPReusablePolicySettings -TemplateInfo $script:TemplateInfo -Tenant 'contoso.onmicrosoft.com'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
        $Result.RawJSON | Should -Be '{"ref":"created-id"}'
    }
}
