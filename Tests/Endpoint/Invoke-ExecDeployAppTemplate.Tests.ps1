# Pester tests for Invoke-ExecDeployAppTemplate: deploying one application of a template, as the Applications
# page does for packages, and the assignment override it sends.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, $TableName, $Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Resolve-CippBulkSelectedTenant { param($Request, $SelectedTenants) $SelectedTenants }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertFrom-CippAppConfig.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/Invoke-ExecDeployAppTemplate.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Template = [pscustomobject]@{
        JSON = (@{ Apps = @(
                    @{ appType = 'win32PackageApp'; appName = 'Contoso Agent'; config = (@{ applicationName = 'Contoso Agent'; packageId = 'p1'; AssignTo = 'AllDevices' } | ConvertTo-Json -Compress) }
                    @{ appType = 'macOSPackageApp'; appName = 'Contoso for Mac'; config = (@{ applicationName = 'Contoso for Mac'; packageId = 'p2' } | ConvertTo-Json -Compress) }
                ) } | ConvertTo-Json -Depth 5 -Compress)
    }
    function New-DeployRequest {
        param([hashtable]$Body)
        [pscustomobject]@{ Body = [pscustomobject](@{ templateId = 't1'; selectedTenants = @([pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com'; customerId = 'c1' }) } + $Body); Headers = @{}; Params = @{ CIPPEndpoint = 'ExecDeployAppTemplate' }; Query = @{} }
    }
}

Describe 'Invoke-ExecDeployAppTemplate' {
    BeforeEach {
        $script:Queued = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:Template }
        Mock Add-CIPPAzDataTableEntity { $script:Queued.Add(($Entity.JSON | ConvertFrom-Json)) }
    }

    It 'queues every application of the template without appName' {
        $Response = Invoke-ExecDeployAppTemplate -Request (New-DeployRequest @{}) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:Queued.Applicationname | Should -Be @('Contoso Agent', 'Contoso for Mac')
    }

    It 'queues only the named application' {
        $Response = Invoke-ExecDeployAppTemplate -Request (New-DeployRequest @{ appName = 'Contoso for Mac' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:Queued.Count | Should -Be 1
        $script:Queued[0].type | Should -Be 'MacOSPackageApp'
        $script:Queued[0].tenant | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'refuses an application that is not in the template' {
        $Response = Invoke-ExecDeployAppTemplate -Request (New-DeployRequest @{ appName = 'Fabrikam' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
        $script:Queued.Count | Should -Be 0
    }

    It 'applies picked groups and exclusions sent with an assignment override' {
        $null = Invoke-ExecDeployAppTemplate -Request (New-DeployRequest @{ appName = 'Contoso Agent'; AssignTo = 'customGroup'; customGroup = 'Pilot'; GroupIds = @('g1'); excludeGroup = 'Kiosks'; ExcludeGroupIds = @('g2') }) -TriggerMetadata $null

        $script:Queued[0].assignTo | Should -Be 'Pilot'
        $script:Queued[0].GroupIds | Should -Be @('g1')
        $script:Queued[0].excludeGroup | Should -Be 'Kiosks'
        $script:Queued[0].ExcludeGroupIds | Should -Be @('g2')
    }

    It 'keeps the template assignment without an override' {
        $null = Invoke-ExecDeployAppTemplate -Request (New-DeployRequest @{ appName = 'Contoso Agent' }) -TriggerMetadata $null

        $script:Queued[0].assignTo | Should -Be 'AllDevices'
    }
}
