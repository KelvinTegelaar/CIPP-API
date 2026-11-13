# A tenant group request reaches ExecCIPPDBCache as AllTenants with the request scope narrowed to the group, so
# Get-Tenants lists the group's tenants. The run gets its own name so it neither blocks nor is blocked by an
# all-tenants run, and the queue and messages name the group.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ExecCIPPDBCache.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Resolve-CIPPCommand { param($Name) $true }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-TenantGroups { param($GroupId) }
    function New-CippQueueEntry { param($Name, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev) }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }

    . $FunctionPath
}

Describe 'Invoke-ExecCIPPDBCache tenant group runs' {
    BeforeEach {
        $env:CIPPRootPath = $TestDrive
        $script:Orchestration = $null
        $script:QueueName = $null
        Mock Get-Tenants { 'a.com', 'b.com' | ForEach-Object { [pscustomobject]@{ defaultDomainName = $_ } } }
        Mock Get-TenantGroups { [pscustomobject]@{ Id = $GroupId; Name = 'VIP Clients' } }
        Mock New-CippQueueEntry { $script:QueueName = $Name; [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Start-CIPPOrchestrator { $script:Orchestration = $InputObject; 'instance-1' }
    }

    It 'runs a group as its own orchestration over the group''s tenants' {
        $Response = Invoke-ExecCIPPDBCache -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecCIPPDBCache' }; Headers = @{}; Query = @{ Name = 'Users'; TenantFilter = 'AllTenants'; tenantGroup = 'g1' } }) -TriggerMetadata $null

        [int]$Response.StatusCode | Should -Be 200
        $script:Orchestration.OrchestratorName | Should -Be 'CIPPDBCache_Users_Group_g1'
        @($script:Orchestration.Batch.TenantFilter) | Should -Be @('a.com', 'b.com')
        $script:QueueName | Should -Be 'Users Cache Sync (VIP Clients)'
        $Response.Body.Results | Should -Match 'tenant group VIP Clients'
    }

    It 'keeps the all-tenants run name without a group' {
        $null = Invoke-ExecCIPPDBCache -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecCIPPDBCache' }; Headers = @{}; Query = @{ Name = 'Users'; TenantFilter = 'AllTenants' } }) -TriggerMetadata $null

        $script:Orchestration.OrchestratorName | Should -Be 'CIPPDBCache_Users_AllTenants'
        $script:QueueName | Should -Be 'Users Cache Sync (All Tenants)'
    }
}
