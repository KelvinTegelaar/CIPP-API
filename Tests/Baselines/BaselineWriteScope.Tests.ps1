BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-Tenants {
        param($TenantFilter, [switch]$IncludeErrors)
        @(
            [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
            [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }
        )
    }
    function Get-TenantGroups { }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) [pscustomobject]@{ RowKey = 'baseline-1'; templateName = 'Baseline' } }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CIPPBaseline { param($ID) [pscustomobject]@{ assignments = @($script:SavedAssignments); stages = @() } }
    function Get-CIPPBaselineDefinition { param($Name) [pscustomobject]@{ name = $Name } }
    function New-CIPPBaseline { param($Baseline, $User, $LocalChanges) }
    function Test-CIPPRepoSource { param($Source) $false }
    function Invoke-CIPPBaselineMigration { param($TemplateIds, $ReportOnly, $AddDetectStandards, $User, [switch]$Preview) @{ summary = @{} } }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Authentication/Get-CippRequestContext.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineOutOfScopeAssignment.ps1')
    $StandardsPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards'
    foreach ($Name in 'Invoke-AddBaseline', 'Invoke-ExecBaselineAddStandard', 'Invoke-RemoveBaseline', 'Invoke-ExecBaselineMigrate') {
        . (Join-Path $StandardsPath "$Name.ps1")
    }

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
    function New-Request($Body) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'Test' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Query = @{}; Body = [pscustomobject]$Body }
    }
    function Set-AllowedTenants($Tenants) {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedTenantsStorage.Value = $Tenants
    }
}

Describe 'Baseline writes for a tenant-restricted caller' {
    BeforeEach {
        Set-AllowedTenants @('tenant-1')
        $script:SavedAssignments = @([pscustomobject]@{ label = 't2.example.com'; value = 't2.example.com' })
        Mock New-CIPPBaseline { [pscustomobject]@{ GUID = 'baseline-1'; DeltaCount = 0 } }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Invoke-CIPPBaselineMigration { @{ summary = @{} } }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'refuses to remove a baseline assigned to a tenant outside their access' {
        (Invoke-RemoveBaseline -Request (New-Request @{ ID = 'baseline-1' })).StatusCode | Should -Be 403
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'removes a baseline assigned only to their tenants' {
        $script:SavedAssignments = @([pscustomobject]@{ label = 't1.example.com'; value = 't1.example.com' })
        (Invoke-RemoveBaseline -Request (New-Request @{ ID = 'baseline-1' })).StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'baseline-1' }
    }

    It 'refuses to add a standard to a baseline assigned to a tenant outside their access' {
        (Invoke-ExecBaselineAddStandard -Request (New-Request @{ baselineId = 'baseline-1'; standard = 'Example' })).StatusCode | Should -Be 403
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'refuses to save an edit that drops a saved assignment outside their access' {
        $Body = @{ GUID = 'baseline-1'; templateName = 'Baseline'; assignedTenants = @([pscustomobject]@{ label = 't1.example.com'; value = 't1.example.com' }) }
        (Invoke-AddBaseline -Request (New-Request $Body)).StatusCode | Should -Be 403
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'refuses to assign a new baseline to <Value>' -ForEach @(
        @{ Value = 't2.example.com' }
        @{ Value = 'AllTenants' }
    ) {
        $Body = @{ templateName = 'Baseline'; assignedTenants = @([pscustomobject]@{ label = $Value; value = $Value }) }
        (Invoke-AddBaseline -Request (New-Request $Body)).StatusCode | Should -Be 403
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'saves a new baseline assigned to their own tenant' {
        $Body = @{ templateName = 'Baseline'; assignedTenants = @([pscustomobject]@{ label = 't1.example.com'; value = 't1.example.com' }) }
        (Invoke-AddBaseline -Request (New-Request $Body)).StatusCode | Should -Be 200
        Should -Invoke New-CIPPBaseline -Times 1
    }

    It 'refuses to migrate templates to baselines but still previews them' {
        (Invoke-ExecBaselineMigrate -Request (New-Request @{ action = 'commit' })).StatusCode | Should -Be 403
        Should -Invoke Invoke-CIPPBaselineMigration -Times 0
        (Invoke-ExecBaselineMigrate -Request (New-Request @{ action = 'preview' })).StatusCode | Should -Be 200
        Should -Invoke Invoke-CIPPBaselineMigration -Times 1 -ParameterFilter { $Preview }
    }

    It 'lets an unrestricted caller migrate and remove anything' {
        Set-AllowedTenants $null
        (Invoke-ExecBaselineMigrate -Request (New-Request @{ action = 'commit' })).StatusCode | Should -Be 200
        (Invoke-RemoveBaseline -Request (New-Request @{ ID = 'baseline-1' })).StatusCode | Should -Be 200
    }
}
