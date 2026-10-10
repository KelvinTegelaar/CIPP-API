# Pester tests for Invoke-ListApiEgress
# Craft's egress table carries an 'interactive' partition (signed-in users, never capped) and a
# compact per-endpoint JSON column. This pins that interactive traffic stays out of the API client
# figures, and that endpoint maps expand for the instance, each client, interactive and each bucket.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ListApiEgress.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($API, $message, $sev, $LogData) }

    . $FunctionPath

    $script:App = '11111111-1111-1111-1111-111111111111'
    $Today = [DateTime]::UtcNow.ToString('yyyyMMdd')
    $Bucket = 'bkt_{0}T000000Z' -f $Today

    $script:DayRows = @(
        [pscustomobject]@{ PartitionKey = $script:App; RowKey = "day_$Today"; Bytes = 1000; Requests = 4; Shed = 0; Endpoints = '{"ListUsers":[900,3,500,1,0,0],"ListGraphRequest:users":[100,1,100,0,1,0]}' }
        [pscustomobject]@{ PartitionKey = 'interactive'; RowKey = "day_$Today"; Bytes = 5000; Requests = 2; Shed = 0; Endpoints = '{"ListLogs":[5000,2,4000,0,0,0]}' }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = "day_$Today"; Bytes = 1000; Requests = 4; Shed = 0; CapBytes = 0; Endpoints = '{"ListUsers":[900,3,500,1,0,0],"ListGraphRequest:users":[100,1,100,0,1,0]}' }
    )
    $script:BucketRows = @(
        [pscustomobject]@{ PartitionKey = $script:App; RowKey = $Bucket; Bytes = 1000; Requests = 4; BucketStartUtc = [DateTime]::UtcNow.Date }
        [pscustomobject]@{ PartitionKey = 'interactive'; RowKey = $Bucket; Bytes = 5000; Requests = 2; BucketStartUtc = [DateTime]::UtcNow.Date; Endpoints = '{"ListLogs":[5000,2,4000,0,0,0]}' }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = $Bucket; Bytes = 1000; Requests = 4; BucketStartUtc = [DateTime]::UtcNow.Date; Endpoints = '{"ListUsers":[900,3,500,1,0,0],"ListGraphRequest:users":[100,1,100,0,1,0]}' }
    )
}

Describe 'Invoke-ListApiEgress endpoint breakdown' {
    BeforeEach {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:DayRows } -ParameterFilter { $Filter -like "RowKey eq 'day_*" }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:BucketRows } -ParameterFilter { $Filter -like 'RowKey ge*' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @([pscustomobject]@{ RowKey = $script:App; AppName = 'Acme RMM' }) } -ParameterFilter { $TableName -eq 'ApiClients' }
    }

    It 'keeps signed-in user traffic out of the API client figures' {
        $Results = (Invoke-ListApiEgress -Request ([pscustomobject]@{ Params = @{}; Query = @{} }) -TriggerMetadata $null).Body.Results

        $Results.Clients | Should -HaveCount 1
        $Results.Clients[0].Name | Should -Be 'Acme RMM'
        $Results.ClientIds | Should -Be @($script:App)
        $Results.Interactive.Bytes | Should -Be 5000
        $Results.Interactive.Endpoints[0].Endpoint | Should -Be 'ListLogs'
    }

    It 'expands endpoint maps largest first with derived averages' {
        $Results = (Invoke-ListApiEgress -Request ([pscustomobject]@{ Params = @{}; Query = @{} }) -TriggerMetadata $null).Body.Results

        $Results.Endpoints.Endpoint | Should -Be @('ListUsers', 'ListGraphRequest:users')
        $Results.Endpoints[0].AvgBytes | Should -Be 300
        $Results.Endpoints[0].CacheHits | Should -Be 1
        $Results.Endpoints[1].Errors | Should -Be 1
        $Results.Clients[0].Endpoints | Should -HaveCount 2
        $Results.Trend | Should -HaveCount 1
        $Results.Trend[0].TopEndpoints[0].Endpoint | Should -Be 'ListUsers'
    }
}
