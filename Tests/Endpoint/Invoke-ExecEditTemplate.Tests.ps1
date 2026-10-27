BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, $OperationType) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecEditTemplate.ps1')

    function Invoke-Edit($Type) {
        Invoke-ExecEditTemplate -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEditTemplate' }
                Headers = @{}
                Query   = @{ Type = $Type }
                Body    = [pscustomobject]@{ GUID = 'template-1'; displayName = 'x' }
            })
    }
}

Describe 'Invoke-ExecEditTemplate template types' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity { } }

    It 'refuses to write a <Type> template' -ForEach @(
        @{ Type = 'StandardsTemplateV2' }
        @{ Type = 'GroupTemplate' }
        @{ Type = $null }
    ) {
        (Invoke-Edit $Type).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'saves a CATemplate' {
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq 'CATemplate' }
    }
}
