# The list of custom managed baseline requests, what was sent for one of them, and the delivered
# baseline in the shape the baseline editor loads.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPManagedBaselineRequestBody { param($Row) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Merge-CIPPManagedBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ListManagedBaselineRequests.ps1')

    $script:NewRequest = {
        param($Query = @{})
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListManagedBaselineRequests' }; Headers = @{}; Query = [pscustomobject]$Query }
    }
    function New-Row {
        param($Id, $Status, $CreatedAt, $Extra = @{})
        $Row = @{
            PartitionKey = 'request'; RowKey = $Id; TenantFilter = 'contoso.com'; Status = $Status; CreatedAt = $CreatedAt
            Industry = 'Healthcare'; ClientSize = '26-100'; Wants = 'Pass the questionnaire'
            Frameworks = '["CIS"]'; Total = 227
        }
        foreach ($Key in $Extra.Keys) { $Row[$Key] = $Extra[$Key] }
        [pscustomobject]$Row
    }
    $Config = { param($Standard, $Instance, $Variables = @{}) [pscustomobject]@{ standard = $Standard; instance = $Instance; variables = [pscustomobject]$Variables; remediateEnabled = $false; alertEnabled = $true; alertOnRemediate = $false } }
    $script:Package = [pscustomobject]@{
        id       = 'custom-1'
        version  = 2
        Baseline = [pscustomobject]@{
            templateName        = 'Custom baseline'
            description         = 'Built by CyberDrain'
            stages              = @([pscustomobject]@{
                    name = 'Baseline'; logic = 'and'; conditionGroups = @()
                    conditions = @([pscustomobject]@{ type = 'group'; group = 'someone-elses-group' })
                    standards = @((& $Config 'SmartLockout' 'SmartLockout'), (& $Config 'ConditionalAccessTemplate' 'ConditionalAccessTemplate#1' @{ caTemplate = 'tpl-1' }))
                })
            referencedTemplates = @([pscustomobject]@{ partition = 'CATemplate'; guid = 'tpl-1'; displayName = 'Block legacy authentication' })
        }
    }
}

Describe 'Invoke-ListManagedBaselineRequests' {
    BeforeEach {
        $script:Requests = @()
        $script:Rollouts = @()
        Mock Write-LogMessage {}
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com'; displayName = 'Contoso Ltd' } }
        Mock Get-CIPPBaselineDefinition {
            [pscustomobject]@{ name = 'SmartLockout'; label = 'Configure Smart Lockout' }
            [pscustomobject]@{ name = 'ConditionalAccessTemplate'; instanceIdentity = 'caTemplate'; variables = [pscustomobject]@{ caTemplate = [pscustomobject]@{ type = 'autoComplete' } } }
        }
        Mock Get-CIPPAzDataTableEntity {
            switch ($Context) {
                'ManagedBaselineRequests' { $script:Requests }
                'BaselineRollouts' { $script:Rollouts }
                'ManagedBaselineCollection' { 1..3 | ForEach-Object { [pscustomobject]@{ RowKey = "standard-$_" } } }
            }
        }
    }

    Context 'the list' {
        It 'lists requests newest first, with what was typed and how far collection is' {
            $script:Requests = @(
                New-Row 'older' 'Waiting on CyberDrain' 100
                New-Row 'newer' 'Waiting on data collection' 200
            )

            $Response = Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest)

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results.requestId | Should -Be @('newer', 'older')
            $Newer = $Response.Body.Results[0]
            $Newer.status | Should -Be @('Waiting on data collection')
            $Newer.collected | Should -Be 3
            $Newer.total | Should -Be 227
            $Newer.tenantFilter | Should -Be 'contoso.com'
            $Newer.frameworks | Should -Be @('CIS')
            $Response.Body.Results[1].collected | Should -BeNullOrEmpty
        }

        It 'shows the baseline a request became, and when CyberDrain has a newer version of it' {
            $script:Requests = @(New-Row 'request-9' 'Implemented' 100 @{ RemoteVersion = '3' })
            $script:Rollouts = @([pscustomobject]@{ RowKey = 'baseline-1'; templateName = 'Contoso baseline'; ManagedRequestId = 'request-9'; ManagedVersion = '2' })

            $Row = (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest)).Body.Results[0]

            $Row.status | Should -Be @('Implemented', 'Update available')
            $Row.baselineGuid | Should -Be 'baseline-1'
            $Row.baselineName | Should -Be 'Contoso baseline'
            $Row.ready | Should -BeFalse
        }

        It 'marks a delivered request as ready to confirm' {
            $script:Requests = @(New-Row 'request-9' 'Completed - ready to confirm' 100)

            (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest)).Body.Results[0].ready | Should -BeTrue
        }

        It 'only lists requests for tenants the caller can access' {
            $script:Requests = @((New-Row 'mine' 'Failed' 100), (New-Row 'theirs' 'Failed' 200))
            Mock Select-CippAllowedTenantData { process { if ($InputObject.RowKey -eq 'mine') { $InputObject } } }

            (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest)).Body.Results.requestId | Should -Be @('mine')
        }
    }

    Context 'one request' {
        BeforeEach {
            $script:Requests = @(New-Row 'request-9' 'Completed - ready to confirm' 100)
            Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; version = 2; package = $script:Package } }
        }

        It 'returns exactly what was sent' {
            Mock Get-CIPPManagedBaselineRequestBody { [ordered]@{ requestId = 'request-9'; standards = @() } }

            $Response = Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest @{ requestId = 'request-9' })

            $Response.Body.Results.requestId | Should -Be 'request-9'
            Should -Invoke Get-CIPPManagedBaselineRequestBody -Times 1 -Exactly -ParameterFilter { $Row.RowKey -eq 'request-9' }
            Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
        }

        It 'returns the delivered baseline as the editor loads one, with the tenant already selected' {
            $Baseline = (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest @{ requestId = 'request-9'; includeBaseline = 'true' })).Body.Results

            $Baseline.GUID | Should -Be 'managed-request-request-9'
            $Baseline.templateName | Should -Be 'Custom baseline'
            $Baseline.assignments[0].value | Should -Be 'contoso.com'
            $Baseline.assignments[0].label | Should -Be 'Contoso Ltd (contoso.com)'
            $Baseline.managedRequestId | Should -Be 'request-9'
            $Baseline.managedVersion | Should -Be '2'
            $Baseline.stages[0].standards | Should -Be @('SmartLockout', 'ConditionalAccessTemplate#1')
            $Baseline.stages[0].standardsConfig.Count | Should -Be 2
        }

        It 'names the templates the baseline refers to, and drops conditions that point at someone else''s groups' {
            $Stage = (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest @{ requestId = 'request-9'; includeBaseline = 'true' })).Body.Results.stages[0]

            $Picker = ($Stage.standardsConfig | Where-Object { $_.standard -eq 'ConditionalAccessTemplate' }).variables.caTemplate
            $Picker.label | Should -Be 'Block legacy authentication'
            $Picker.value | Should -Be 'tpl-1'
            @($Stage.conditions).Count | Should -Be 0
        }

        It 'refuses the delivered baseline before CyberDrain has delivered one' {
            Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'in-progress' } }

            (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest @{ requestId = 'request-9'; includeBaseline = 'true' })).StatusCode | Should -Be 400
        }

        It 'answers not found for a request the caller cannot see' {
            $script:Requests = @()

            (Invoke-ListManagedBaselineRequests -Request (& $script:NewRequest @{ requestId = 'request-9' })).StatusCode | Should -Be 404
        }
    }
}
