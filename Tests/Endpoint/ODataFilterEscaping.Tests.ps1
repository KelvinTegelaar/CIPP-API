BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) $script:Filters.Add([string]$Filter) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) @('AllTenants') }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    $Http = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    foreach ($Name in 'Invoke-ExecSharePointTemplate', 'Invoke-ExecAppApprovalTemplate', 'Invoke-ExecAppPermissionTemplate', 'Invoke-ExecGraphExplorerPreset', 'Invoke-ExecPushSubscription', 'Invoke-ExecRemoveCippCveException') {
        . (Get-ChildItem -Path $Http -Recurse -Filter "$Name.ps1").FullName
    }

    $Inject = "x' or PartitionKey ne '"
    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"user@contoso.com"}'))
    function New-Request($Body, $Query = @{}) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'Test' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Query = $Query; Body = [pscustomobject]$Body }
    }
}

Describe 'Request values are escaped in table filters' {
    BeforeEach { $script:Filters = [System.Collections.Generic.List[string]]::new() }

    It '<Name> keeps a crafted id inside its quotes' -ForEach @(
        @{ Name = 'ExecSharePointTemplate delete'; Call = { Invoke-ExecSharePointTemplate -Request (New-Request @{ Action = 'Delete'; TemplateId = $Inject }) } }
        @{ Name = 'ExecAppApprovalTemplate delete'; Call = { Invoke-ExecAppApprovalTemplate -Request (New-Request @{ Action = 'Delete'; TemplateId = $Inject }) } }
        @{ Name = 'ExecAppPermissionTemplate delete'; Call = { Invoke-ExecAppPermissionTemplate -Request (New-Request @{ Action = 'Delete'; TemplateId = $Inject }) } }
        @{ Name = 'ExecGraphExplorerPreset delete'; Call = { Invoke-ExecGraphExplorerPreset -Request (New-Request @{ action = 'Delete'; preset = [pscustomobject]@{ id = $Inject; name = 'p'; endpoint = 'users' } }) } }
        @{ Name = 'ExecPushSubscription unsubscribe'; Call = { Invoke-ExecPushSubscription -Request (New-Request @{ Action = 'Unsubscribe'; RowKey = $Inject }) } }
        @{ Name = 'ExecRemoveCippCveException'; Call = { Invoke-ExecRemoveCippCveException -Request (New-Request @{ cveId = $Inject; removeScope = 'AllAffected' }) } }
    ) {
        & $Call | Out-Null
        $Crafted = @($script:Filters).Where({ $_ -like '*x*or PartitionKey ne*' })
        $Crafted.Count | Should -BeGreaterThan 0
        foreach ($Filter in $Crafted) { $Filter | Should -BeLike "*'x'' or PartitionKey ne '''*" }
    }
}
