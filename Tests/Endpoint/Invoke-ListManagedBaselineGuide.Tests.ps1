# The implementation guide CyberDrain ships with a managed baseline, read from its package.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ListManagedBaselineGuide.ps1')

    $Samples = Join-Path $BackendRoot 'Tests/Fixtures/ManagedBaselines'
    $script:Template = Get-Content (Join-Path $Samples 'template-sample-email-protection.json') -Raw | ConvertFrom-Json -Depth 100
    $script:Custom = Get-Content (Join-Path $Samples 'custom-package.json') -Raw | ConvertFrom-Json -Depth 100
    function New-GuideRequest { param($Query) [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListManagedBaselineGuide' }; Headers = @{}; Query = [pscustomobject]$Query } }
}

Describe 'Invoke-ListManagedBaselineGuide' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Invoke-ManagedBaselinesRequest { $script:Template } -ParameterFilter { $Path -like 'templates/*' }
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; package = $script:Custom } } -ParameterFilter { $Path -like 'requests/*' }
        Mock Get-CIPPAzDataTableEntity {}
    }

    It 'returns the overview and every stage in the order of the baseline' {
        $Response = Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{ id = 'sample-email-protection' })

        $Response.StatusCode | Should -Be 200
        $Guide = $Response.Body.Results
        $Guide.name | Should -Be 'Sample - Email Protection'
        $Guide.version | Should -Be '1'
        $Guide.overview | Should -BeLike '*Before you start*'
        @($Guide.stages.name) | Should -Be @('Baseline', 'Hardening')
        $Guide.stages[1].guide | Should -BeLike '*Basic authentication*'
        @($Guide.stages[1].communications).Count | Should -Be 2
        $Guide.stages[1].communications[0].audience | Should -Be 'Client contact'
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'templates/sample-email-protection' }
    }

    It 'still lists the stages of a baseline that has no guide' {
        $Bare = $script:Template | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $Bare.PSObject.Properties.Remove('Guide')
        Mock Invoke-ManagedBaselinesRequest { $Bare } -ParameterFilter { $Path -like 'templates/*' }

        $Guide = (Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{ id = 'sample-email-protection' })).Body.Results

        $Guide.overview | Should -BeNullOrEmpty
        @($Guide.stages.name) | Should -Be @('Baseline', 'Hardening')
        @($Guide.stages[0].communications).Count | Should -Be 0
    }

    It 'finds the published baseline behind a baseline that was added' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'baseline-a'; ManagedId = 'sample-email-protection'; ManagedVersion = '0'; ManagedKind = 'template' } }

        $Guide = (Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{ GUID = 'baseline-a' })).Body.Results

        $Guide.importedVersion | Should -Be '0'
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'templates/sample-email-protection' }
    }

    It 'reads the guide of a custom baseline from its request' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'baseline-c'; ManagedId = 'sample-custom'; ManagedVersion = '1'; ManagedKind = 'custom'; ManagedRequestId = 'request-9' } }

        $Guide = (Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{ GUID = 'baseline-c' })).Body.Results

        $Guide.name | Should -Be 'Sample - Custom Baseline'
        @($Guide.stages[0].communications).Count | Should -Be 1
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'requests/request-9' }
    }

    It 'refuses a baseline CyberDrain does not manage' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'baseline-d'; templateName = 'An ordinary baseline' } }

        $Response = Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{ GUID = 'baseline-d' })

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
    }

    It 'refuses a call that names no baseline' {
        (Invoke-ListManagedBaselineGuide -Request (New-GuideRequest @{})).StatusCode | Should -Be 400
    }
}
