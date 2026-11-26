# A template with an undefined variable must stop before the batch writes any shared named location.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCAUnresolvedVariable.ps1')

    function Set-CIPPDBCacheConditionalAccessPolicies { param($TenantFilter) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function New-CIPPDbRequest { param($TenantFilter, $Type) @() }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $asapp) @() }
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $asApp, [switch]$ComplexFilter) @() }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CippAzDataTableEntity { [CmdletBinding()] param($Filter) [pscustomobject]@{ JSON = $script:Templates[($Filter -replace ".*RowKey eq '([^']+)'.*", '$1')] } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Set-CippStandardInfoContext { param($StandardInfo) }
    function Set-CIPPStandardsCompareField { param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $Tenant, $LicenseAvailable) $script:CompareFields[$FieldName] = $CurrentValue.Differences }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData, $Headers) $script:Logs.Add($message) }
    function Get-NormalizedError { param($Message) $Message }
    function Start-Sleep { param($Seconds) }
    function Resolve-CIPPCADependencies {
        param($TenantFilter, $PolicyObjects, $AllNamedLocations, $AllAuthStrengthPolicies, $Overwrite, $Headers, $APIName)
        foreach ($Policy in $PolicyObjects) { $script:Reconciled.Add($Policy.displayName) }
        @{ Locations = @{}; AuthStrength = @{}; AuthContexts = @{}; NewLocationsCreated = $false }
    }
    function New-CIPPCAPolicy { param($RawJSON) $script:Deployed.Add(($RawJSON | ConvertFrom-Json).displayName) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPCATemplateBatch.ps1')

    function New-BatchTemplate {
        param($Id, $Name)
        [pscustomobject]@{ TemplateId = 'standards-template'; Settings = [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = $Id; label = $Name }; remediate = $true; state = 'donotchange' } }
    }
}

Describe 'Invoke-CIPPCATemplateBatch undefined variables' {
    BeforeEach {
        $script:CompareFields = @{}
        $script:Logs = [System.Collections.Generic.List[string]]::new()
        $script:Reconciled = [System.Collections.Generic.List[string]]::new()
        $script:Deployed = [System.Collections.Generic.List[string]]::new()
        $script:Templates = @{
            bad  = '{"displayName":"Bad policy","conditions":{"users":{"includeUsers":["All"]},"locations":{"includeLocations":["All"],"excludeLocations":["Office IPs"]}},"LocationInfo":[{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Office IPs","ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"%branchips%"}]}]}'
            good = '{"displayName":"Good policy","conditions":{"users":{"includeUsers":["All"]}}}'
        }
        Invoke-CIPPCATemplateBatch -Tenant 'customer.example.com' -Templates @((New-BatchTemplate -Id 'bad' -Name 'Bad policy'), (New-BatchTemplate -Id 'good' -Name 'Good policy'))
    }

    It 'keeps the policy out of dependency reconciliation and deployment' {
        @($script:Reconciled) | Should -Be @('Good policy')
        @($script:Deployed) | Should -Be @('Good policy')
    }

    It 'reports the variable and the tenant' {
        $script:CompareFields['standards.ConditionalAccessTemplate.bad'] | Should -BeLike 'Failed to deploy: *uses %branchips%, which is not defined for customer.example.com*'
        @($script:Logs -like '*uses %branchips%, which is not defined for customer.example.com*').Count | Should -Be 1
    }
}
