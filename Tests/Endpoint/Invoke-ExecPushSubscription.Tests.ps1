# Pester tests for Invoke-ExecPushSubscription.
#
# Pins the ownership rules of push devices: a subscription is stored under the calling
# principal keyed by its endpoint, only its owner can remove it, and nothing changes while
# the caller is impersonating a role.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecPushSubscription.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecPushSubscription.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Send-CIPPAlert { param($Type, $TargetUser, $Title, $PushMessage, $Url, $APIName) }
    function Get-StringHash { param($String) }

    . $FunctionPath

    function New-Request {
        param($Body, [string]$User = 'tech@msp.example', [string]$Impersonate)
        $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $User } | ConvertTo-Json -Compress)))
        $Headers = @{ 'x-ms-client-principal' = $Principal }
        if ($Impersonate) { $Headers['x-cipp-impersonate-role'] = $Impersonate }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecPushSubscription' }
            Headers = $Headers
            Body    = $Body
        }
    }
    $script:Subscription = [pscustomobject]@{
        endpoint = 'https://push.example/send/abc'
        keys     = [pscustomobject]@{ p256dh = 'BPUB'; auth = 'AUTH' }
    }
}

Describe 'Invoke-ExecPushSubscription' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-StringHash { 'hash-of-endpoint' }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-AzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Send-CIPPAlert { 'Push sent to 1 of 1 device(s)' }
    }

    It 'stores a subscription under the caller keyed by the endpoint hash' {
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Body ([pscustomobject]@{ Action = 'Subscribe'; Subscription = $script:Subscription; DeviceName = 'iOS Safari (app)' }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.RowKey | Should -Be 'hash-of-endpoint'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.PartitionKey -eq 'tech@msp.example' -and $Entity.RowKey -eq 'hash-of-endpoint' -and
            $Entity.Endpoint -eq 'https://push.example/send/abc' -and $Entity.P256dh -eq 'BPUB' -and $Entity.Auth -eq 'AUTH' -and $Entity.DeviceName -eq 'iOS Safari (app)'
        }
    }

    It 'rejects a subscription without an https endpoint or keys' {
        $Bad = [pscustomobject]@{ endpoint = 'http://push.example/x'; keys = [pscustomobject]@{ p256dh = 'BPUB'; auth = 'AUTH' } }
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Body ([pscustomobject]@{ Action = 'Subscribe'; Subscription = $Bad }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses every action while impersonating' {
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Impersonate 'readonly' -Body ([pscustomobject]@{ Action = 'Subscribe'; Subscription = $script:Subscription }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'impersonating'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'only removes a device that belongs to the caller' {
        Mock Get-CIPPAzDataTableEntity { $null }
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Body ([pscustomobject]@{ Action = 'Unsubscribe'; RowKey = 'someone-elses' }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -eq "PartitionKey eq 'tech@msp.example' and RowKey eq 'someone-elses'" }
        Should -Invoke Remove-AzDataTableEntity -Times 0

        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'tech@msp.example'; RowKey = 'mine'; DeviceName = 'Laptop' } }
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Body ([pscustomobject]@{ Action = 'Unsubscribe'; RowKey = 'mine' }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-AzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'mine' }
    }

    It 'sends the test push to the caller only' {
        $Response = Invoke-ExecPushSubscription -Request (New-Request -Body ([pscustomobject]@{ Action = 'Test' }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' -and $TargetUser -eq 'tech@msp.example' }
    }
}
