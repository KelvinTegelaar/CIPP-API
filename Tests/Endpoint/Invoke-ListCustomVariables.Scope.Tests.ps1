# The variable picker's allTenants mode lists every tenant-specific variable name for template editing.
# A caller whose roles cover only some tenants must only see names from those tenants.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListCustomVariables.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $message, $Sev) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Select-CippAllowedTenantData.ps1')

    $script:VariableRows = @(
        [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'GlobalVar'; Value = 'g' }
        [pscustomobject]@{ PartitionKey = 'tenant-1'; RowKey = 'OwnVar'; Value = '1' }
        [pscustomobject]@{ PartitionKey = 't1.example.com'; RowKey = 'OwnLegacyVar'; Value = '1' }
        [pscustomobject]@{ PartitionKey = 'tenant-2'; RowKey = 'OtherVar'; Value = '2' }
    )
}

AfterAll {
    $script:CippAllowedTenantsStorage = $null
    $script:VariableRows = $null
}

Describe 'Invoke-ListCustomVariables allTenants names' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { if ($Filter -eq "PartitionKey eq 'AllTenants'") { $script:VariableRows[0] } elseif (-not $Filter) { $script:VariableRows } }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com'; initialDomainName = 't1.onmicrosoft.com' } }
    }

    It '<Caller> sees <Expect>' -ForEach @(
        @{ Caller = 'a caller restricted to tenant-1'; Scope = @('tenant-1'); Expect = @('GlobalVar', 'OwnLegacyVar', 'OwnVar') }
        @{ Caller = 'an unrestricted caller'; Scope = $null; Expect = @('GlobalVar', 'OtherVar', 'OwnLegacyVar', 'OwnVar') }
    ) {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $Scope }
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListCustomVariables' }; Query = [pscustomobject]@{ allTenants = $true } }

        $Response = Invoke-ListCustomVariables -Request $Request -TriggerMetadata $null

        @($Response.Body.Results | Where-Object { $_.Type -eq 'custom' } | ForEach-Object { $_.Name } | Sort-Object) | Should -Be $Expect
    }
}
