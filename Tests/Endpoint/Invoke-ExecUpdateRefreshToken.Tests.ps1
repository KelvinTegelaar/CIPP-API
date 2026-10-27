BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippKeyVaultName { 'kv' }
    function Get-CIPPAuthentication { }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Set-CippKeyVaultSecret { param($VaultName, $Name, $SecretValue) }
    function Clear-CippTokenCache { param($TenantFilter) }
    function Set-CIPPCredentialVersion { }
    function New-CippQueueEntry { param($Name, $TotalTasks) @{ RowKey = 'q' } }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Setup/Invoke-ExecUpdateRefreshToken.ps1')

    $script:Partner = '11111111-1111-1111-1111-111111111111'
    $script:Managed = '22222222-2222-2222-2222-222222222222'
    $script:Other = '33333333-3333-3333-3333-333333333333'

    function Invoke-Update($TenantId) {
        Invoke-ExecUpdateRefreshToken -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecUpdateRefreshToken' }
                Headers = @{}
                Body    = [pscustomobject]@{ tenantId = $TenantId; refreshtoken = 'token' }
            })
    }
}

Describe 'Invoke-ExecUpdateRefreshToken tenant scope' {
    BeforeAll {
        $script:SavedTenantId = $env:TenantID
        $script:SavedStorage = $env:AzureWebJobsStorage
        $script:SavedNonLocal = $env:NonLocalHostAzurite
        $env:TenantID = $script:Partner
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=x'
        $env:NonLocalHostAzurite = $null
    }
    AfterAll {
        $env:TenantID = $script:SavedTenantId
        $env:AzureWebJobsStorage = $script:SavedStorage
        $env:NonLocalHostAzurite = $script:SavedNonLocal
    }
    BeforeEach {
        Mock Set-CippKeyVaultSecret { }
        Mock Get-CIPPAzDataTableEntity { if ($Filter -match $script:Managed -or $Filter -match $script:Other) { [pscustomobject]@{ customerId = 'x' } } }
        $script:TenantAccess = @($script:Managed)
    }

    It 'refuses a tenantId of <TenantId>' -ForEach @(
        @{ TenantId = 'contoso.onmicrosoft.com' }
        @{ TenantId = "x' or PartitionKey ne '" }
        @{ TenantId = $null }
    ) {
        (Invoke-Update $TenantId).StatusCode | Should -Be 400
        Should -Invoke Set-CippKeyVaultSecret -Times 0
    }

    It 'refuses a managed tenant outside the caller''s access' {
        (Invoke-Update $script:Other).StatusCode | Should -Be 403
        Should -Invoke Set-CippKeyVaultSecret -Times 0
    }

    It 'refuses the partner tenant when it is outside the caller''s access' {
        (Invoke-Update $script:Partner).StatusCode | Should -Be 403
        Should -Invoke Set-CippKeyVaultSecret -Times 0
    }

    It 'stores the token for <Name>' -ForEach @(
        @{ Name = 'a tenant the caller can access'; Tenant = '22222222-2222-2222-2222-222222222222'; Access = @('22222222-2222-2222-2222-222222222222') }
        @{ Name = 'a tenant CIPP does not manage yet'; Tenant = '44444444-4444-4444-4444-444444444444'; Access = @('22222222-2222-2222-2222-222222222222') }
        @{ Name = 'any tenant for an all-tenant caller'; Tenant = '33333333-3333-3333-3333-333333333333'; Access = @('AllTenants') }
    ) {
        $script:TenantAccess = $Access
        (Invoke-Update $Tenant).StatusCode | Should -Be 200
        Should -Invoke Set-CippKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq $Tenant }
    }
}
