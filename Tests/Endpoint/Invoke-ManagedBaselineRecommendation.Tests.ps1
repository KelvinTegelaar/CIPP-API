# The two recommendations endpoints. Both need the integration, and Generate saves no baseline.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [string]$OperationType) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Start-CIPPManagedBaselineRecommendationScan { param($Tenant, $StartedBy) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Test-CIPPManagedBaselinesEnabled.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecManagedBaselineRecommendation.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ListManagedBaselineRecommendations.ps1')

    $script:Post = { param($Body) [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecManagedBaselineRecommendation' }; Headers = @{}; Body = [pscustomobject]$Body } }
    $script:Get = { param($Query) [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListManagedBaselineRecommendations' }; Headers = @{}; Query = [pscustomobject]$Query } }
}

Describe 'Managed baseline recommendations endpoints' {
    BeforeEach {
        $script:Enabled = $true
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:Rows = @(
            [pscustomobject]@{ RowKey = 'scan'; ScanId = 'scan-2'; Status = 'Finished'; StartedAt = 100; FinishedAt = 200; Total = 2; ListVersion = '7' }
            [pscustomobject]@{ RowKey = 'rec-SmartLockout'; ScanId = 'scan-2'; Standard = 'SmartLockout'; Status = 'Recommended'; Reason = 'Because.'; Variables = '{"LockoutThreshold":5}'; Differences = '[{"Property":"lockoutThreshold","ExpectedValue":5,"ReceivedValue":10}]'; Current = '{"lockoutThreshold":10}'; FirstSeen = 1700000000 }
            [pscustomobject]@{ RowKey = 'rec-Fine'; ScanId = 'scan-2'; Standard = 'Fine'; Status = 'Compliant' }
            [pscustomobject]@{ RowKey = 'rec-OauthConsent'; ScanId = 'scan-2'; Standard = 'OauthConsent'; Status = 'Covered by a baseline'; Variables = '{}' }
            [pscustomobject]@{ RowKey = 'rec-NoData'; ScanId = 'scan-2'; Standard = 'Other'; Status = 'No data' }
        )
        Mock Write-LogMessage {}
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tenant-1'; displayName = 'Contoso Ltd' } }
        Mock Get-CIPPAzDataTableEntity {
            if ($Context -eq 'Extensionsconfig') { return [pscustomobject]@{ config = (@{ CyberDrainManagedBaselines = @{ Enabled = $script:Enabled } } | ConvertTo-Json) } }
            $script:Rows
        }
        Mock Add-CIPPAzDataTableEntity { $script:Written.Add($Entity) }
        Mock Get-CIPPBaselineDefinition { [pscustomobject]@{ name = 'SmartLockout'; label = 'Set the Smart Lockout threshold'; cat = 'Entra (AAD) Standards'; impact = 'Low Impact'; tag = @('CIS') } }
        Mock Start-CIPPManagedBaselineRecommendationScan { [pscustomobject]@{ Total = 2 } }
    }

    It 'refuses <Name> while the integration is off' -ForEach @(
        @{ Name = 'a scan'; Call = { Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Scan'; tenantFilter = 'contoso.com' }) } }
        @{ Name = 'the list'; Call = { Invoke-ListManagedBaselineRecommendations -Request (& $script:Get @{ tenantFilter = 'contoso.com' }) } }
    ) {
        $script:Enabled = $false

        (& $Call).StatusCode | Should -Be 400
        Should -Invoke Start-CIPPManagedBaselineRecommendationScan -Times 0 -Exactly
        Should -Invoke Get-Tenants -Times 0 -Exactly
    }

    It 'refuses a scan of all tenants' {
        $Response = Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Scan'; tenantFilter = 'AllTenants' })

        $Response.StatusCode | Should -Be 400
        Should -Invoke Start-CIPPManagedBaselineRecommendationScan -Times 0 -Exactly
    }

    It 'starts a scan of one tenant' {
        $Response = Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Scan'; tenantFilter = [pscustomobject]@{ value = 'contoso.com' } })

        $Response.StatusCode | Should -Be 200
        Should -Invoke Start-CIPPManagedBaselineRecommendationScan -Times 1 -Exactly -ParameterFilter { $Tenant.customerId -eq 'tenant-1' }
    }

    It 'has no action to schedule scans' {
        $Response = Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Schedule'; tenantFilter = 'contoso.com'; weekly = $true })

        $Response.StatusCode | Should -Be 400
        $script:Written.Count | Should -Be 0
    }

    It 'prepares every recommended row when none is chosen' {
        $Response = Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Generate'; tenantFilter = 'contoso.com'; rows = @() })

        $Response.StatusCode | Should -Be 200
        @($script:Written.Where({ $_.RowKey -eq 'scan' })[0].Selection | ConvertFrom-Json) | Should -Be @('rec-SmartLockout')
    }

    It 'only takes chosen rows that are a recommendation for the tenant' {
        $null = Invoke-ExecManagedBaselineRecommendation -Request (& $script:Post @{ Action = 'Generate'; tenantFilter = 'contoso.com'; rows = @('rec-OauthConsent', 'rec-Fine', 'rec-NoData') })

        @($script:Written.Where({ $_.RowKey -eq 'scan' })[0].Selection | ConvertFrom-Json) | Should -Be @('rec-OauthConsent')
    }

    It 'lists only what the tenant differs on, with the definition data and the state of the scan' {
        $Body = (Invoke-ListManagedBaselineRecommendations -Request (& $script:Get @{ tenantFilter = 'contoso.com' })).Body

        @($Body.Results.rowKey) | Should -Be @('rec-SmartLockout', 'rec-OauthConsent')
        $Standard = $Body.Results[0]
        $Standard.recommendation | Should -Be 'Set the Smart Lockout threshold'
        $Standard.category | Should -Be 'Entra (AAD) Standards'
        $Standard.reason | Should -Be 'Because.'
        $Standard.differsOn | Should -Be @('lockoutThreshold')
        $Standard.firstSeenDateTime | Should -Be 1700000000
        # An empty list is an empty list, never one null entry.
        ($Body.Results[1] | ConvertTo-Json -Depth 5 -Compress) | Should -Match '"differsOn":\[\]'
        ($Body.Results[1] | ConvertTo-Json -Depth 5 -Compress) | Should -Match '"differences":\[\]'
        $Body.Metadata.scan.compared | Should -Be 4
    }

    It 'builds the prepared baseline as one stage with remediation off' {
        $script:Rows[0] | Add-Member -NotePropertyName Selection -NotePropertyValue '["rec-SmartLockout","rec-OauthConsent"]'
        $script:Rows[0] | Add-Member -NotePropertyName SelectedAt -NotePropertyValue 300

        $Draft = (Invoke-ListManagedBaselineRecommendations -Request (& $script:Get @{ tenantFilter = 'contoso.com'; draft = 'true' })).Body.Results

        $Draft.assignments[0].value | Should -Be 'contoso.com'
        @($Draft.stages).Count | Should -Be 1
        @($Draft.stages[0].standards) | Should -Be @('OauthConsent', 'SmartLockout')
        $Standard = @($Draft.stages[0].standardsConfig).Where({ $_.standard -eq 'SmartLockout' })[0]
        $Standard.remediateEnabled | Should -BeFalse
        $Standard.variables.LockoutThreshold | Should -Be 5
    }
}
