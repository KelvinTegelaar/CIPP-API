# The catalog of baselines CyberDrain publishes, marked against what this instance already added.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    function Get-CIPPBaselineDefinition { param($Name) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ListManagedBaselineTemplates.ps1')

    $script:Catalog = @(Get-Content (Join-Path $BackendRoot 'Tests/Fixtures/ManagedBaselines/catalog.json') -Raw | ConvertFrom-Json -Depth 100)
    $script:Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListManagedBaselineTemplates' }; Headers = @{}; Query = [pscustomobject]@{} }
}

Describe 'Invoke-ListManagedBaselineTemplates' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Invoke-ManagedBaselinesRequest { $script:Catalog }
        Mock Get-CIPPBaselineDefinition { [pscustomobject]@{ name = 'SmartLockout'; label = 'Configure Smart Lockout' } }
        Mock Get-CIPPAzDataTableEntity {
            @(
                # Added at the version CyberDrain still publishes.
                [pscustomobject]@{ RowKey = 'baseline-a'; ManagedId = 'sample-email-protection'; ManagedVersion = '1'; ManagedKind = 'template' }
                # Added at an older version than CyberDrain publishes now.
                [pscustomobject]@{ RowKey = 'baseline-b'; ManagedId = 'sample-identity-essentials'; ManagedVersion = '1'; ManagedKind = 'template' }
                # A custom baseline never counts as an added template, whatever its id.
                [pscustomobject]@{ RowKey = 'baseline-c'; ManagedId = 'sample-collaboration-guardrails'; ManagedVersion = '3'; ManagedKind = 'custom' }
                [pscustomobject]@{ RowKey = 'baseline-d'; templateName = 'An ordinary baseline' }
            )
        }
    }

    It 'marks what was already added and what CyberDrain has updated since' {
        $Response = Invoke-ListManagedBaselineTemplates -Request $script:Request

        $Response.StatusCode | Should -Be 200
        $Rows = @{}
        foreach ($Row in $Response.Body.Results) { $Rows[$Row.id] = $Row }
        $Rows.Count | Should -Be 3
        $Rows['sample-email-protection'].status | Should -Be @('Imported')
        $Rows['sample-email-protection'].baselineGuid | Should -Be 'baseline-a'
        $Rows['sample-identity-essentials'].status | Should -Be @('Imported', 'Update available')
        @($Rows['sample-collaboration-guardrails'].status).Count | Should -Be 0
        $Rows['sample-collaboration-guardrails'].imported | Should -BeFalse
    }

    It 'lists one row per baseline when the reply arrives as a single array object' {
        Mock Invoke-ManagedBaselinesRequest { Write-Output -NoEnumerate @($script:Catalog) }

        $Response = Invoke-ListManagedBaselineTemplates -Request $script:Request

        @($Response.Body.Results).Count | Should -Be @($script:Catalog).Count
        @($Response.Body.Results)[0].id | Should -BeOfType [string]
    }

    It 'shows each stage with the friendly name of its standards' {
        $Row = (Invoke-ListManagedBaselineTemplates -Request $script:Request).Body.Results | Where-Object { $_.id -eq 'sample-identity-essentials' }

        $Row.stages[0].name | Should -Be 'Baseline'
        $Row.stages[0].standards | Should -Contain 'Configure Smart Lockout'
        $Row.stages[0].standards | Should -Contain 'PasswordExpireDisabled'
        $Row.tags | Should -Be @('Identity', 'All sizes')
    }

    It 'answers <Status> when the service function refuses with <Type>' -ForEach @(
        @{ Status = 400; Type = 'ArgumentException'; Throw = { throw [System.ArgumentException]::new('The integration is not enabled.') } }
        @{ Status = 403; Type = 'UnauthorizedAccessException'; Throw = { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key.') } }
    ) {
        Mock Invoke-ManagedBaselinesRequest $Throw

        $Response = Invoke-ListManagedBaselineTemplates -Request $script:Request

        $Response.StatusCode | Should -Be $Status
        $Response.Body.Results | Should -BeLike 'Failed to list managed baselines:*'
    }
}
