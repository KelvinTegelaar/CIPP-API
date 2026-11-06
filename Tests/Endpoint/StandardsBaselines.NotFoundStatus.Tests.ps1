# A missing standards template or baseline is a 404 and a bad request is a 400, not a 500: Craft caches nothing for
# 4xx, MCP and the frontend treat 500 as a server fault, and a repeated delete of a template that is already gone must
# say so rather than look like CIPP broke.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Standards = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards'
    foreach ($Name in 'RemoveStandardTemplate', 'RemoveBaseline', 'ExecStandardTemplateSchedule', 'ExecBaselineAddStandard', 'ExecBaselineOverride', 'ExecUpdateBaselineDeviation', 'ListBaselineAlignment') {
        . (Join-Path $Standards "Invoke-$Name.ps1")
    }
    . (Get-ChildItem (Join-Path $BackendRoot 'Modules/CIPPCore') -Recurse -Filter 'Get-CippErrorStatusCode.ps1' | Select-Object -First 1).FullName
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineAlignment.ps1')

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-AzDataTableEntity { param($TableName, $Filter) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed++ }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPBaseline { param($ID) }

    function New-Request($Body = @{}, $Query = @{}) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'Test' }; Headers = @{}; Body = [pscustomobject]$Body; Query = [pscustomobject]$Query }
    }
}

Describe 'Standards and baseline endpoints report missing items as 404' {
    BeforeEach { $script:Removed = 0 }

    It '<Endpoint> returns <Status> for <Case>' -ForEach @(
        @{ Endpoint = 'RemoveStandardTemplate'; Case = 'an unknown template'; Body = @{ ID = '00000000-0000-0000-0000-000000000001' }; Status = 404 }
        @{ Endpoint = 'RemoveStandardTemplate'; Case = 'no id'; Body = @{}; Status = 400 }
        @{ Endpoint = 'RemoveBaseline'; Case = 'an unknown baseline'; Body = @{ ID = 'nope' }; Status = 404 }
        @{ Endpoint = 'RemoveBaseline'; Case = 'no id'; Body = @{}; Status = 400 }
        @{ Endpoint = 'ExecStandardTemplateSchedule'; Case = 'an unknown template'; Body = @{ TemplateId = '00000000-0000-0000-0000-000000000001'; runManually = $true }; Status = 404 }
        @{ Endpoint = 'ExecBaselineAddStandard'; Case = 'an unknown standard'; Body = @{ baselineId = 'b1'; standard = 'NoSuchStandard' }; Status = 404 }
        @{ Endpoint = 'ExecBaselineAddStandard'; Case = 'missing fields'; Body = @{}; Status = 400 }
        @{ Endpoint = 'ExecBaselineOverride'; Case = 'missing fields'; Body = @{}; Status = 400 }
        @{ Endpoint = 'ExecUpdateBaselineDeviation'; Case = 'missing fields'; Body = @{}; Status = 400 }
        @{ Endpoint = 'ListBaselineAlignment'; Case = 'no tenant or byStandard'; Query = @{}; Status = 400 }
        @{ Endpoint = 'ListBaselineAlignment'; Case = 'an unknown baseline'; Query = @{ byStandard = 'true'; baselineId = 'nope' }; Status = 404 }
    ) {
        $Response = & "Invoke-$Endpoint" -Request (New-Request -Body ($Body ?? @{}) -Query ($Query ?? @{})) -TriggerMetadata $null
        $Response.StatusCode | Should -Be $Status
        $script:Removed | Should -Be 0
    }
}
