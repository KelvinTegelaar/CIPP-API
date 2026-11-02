BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Test-CippAccess { param($Request, [switch]$GroupList) $script:GroupAccess }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $headers, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-CippBulkStatusCode { param($Total, $Failed) 200 }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecCreateDefaultGroups.ps1')
}

Describe 'Invoke-ExecCreateDefaultGroups access' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity { } }

    It 'refuses a caller who cannot manage every tenant group' {
        $script:GroupAccess = @('group-1')
        $Response = Invoke-ExecCreateDefaultGroups -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecCreateDefaultGroups' }; Headers = @{} })
        $Response.StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'creates the groups for a caller with all-tenant access' {
        $script:GroupAccess = @('AllGroups')
        $Response = Invoke-ExecCreateDefaultGroups -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecCreateDefaultGroups' }; Headers = @{} })
        $Response.StatusCode | Should -Not -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity
    }
}
