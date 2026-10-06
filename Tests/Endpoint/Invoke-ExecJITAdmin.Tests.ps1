BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPJITAdminAllowedRoles { param($Headers) [pscustomobject]@{ Restricted = $false } }
    function Add-CIPPScheduledTask { param($Task, $hidden, [switch]$RunNow) }
    function Set-CIPPUserJITAdmin { param($TenantFilter, $User, $Roles, $Groups, $Action, $Expiration, $StartDate, $Reason, $Headers, $APIName) }
    function Set-CIPPUserJITAdminProperties { param($TenantFilter, $UserId, $Expiration, $StartDate, $Reason, $CreatedBy) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecJITAdmin.ps1' | Select-Object -First 1).FullName

    function New-Request {
        param([int]$StartOffsetSeconds)
        $Now = [DateTimeOffset]::UtcNow
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@contoso.com"}'))
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecJITAdmin' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                userAction      = 'existing'
                existingUser    = [pscustomobject]@{ value = 'jit@contoso.com' }
                AdminRoles      = @([pscustomobject]@{ value = '62e90394-69f5-4237-9190-012177145e10' })
                ExpireAction    = [pscustomobject]@{ value = 'RemoveRoles' }
                Reason          = 'Break glass'
                StartDate       = $Now.AddSeconds($StartOffsetSeconds).ToUnixTimeSeconds()
                EndDate         = $Now.AddDays(1).ToUnixTimeSeconds()
                PostExecution   = @([pscustomobject]@{ value = 'webhook' }, [pscustomobject]@{ value = 'Push' })
            }
        }
    }
}

Describe 'Invoke-ExecJITAdmin enable scheduling' {
    BeforeEach {
        Mock Add-CIPPScheduledTask { }
        Mock Set-CIPPUserJITAdmin { }
        Mock Set-CIPPUserJITAdminProperties { }
    }

    It 'queues the enable task to run now with the requested notification channels when the start is immediate' {
        $Response = Invoke-ExecJITAdmin -Request (New-Request -StartOffsetSeconds 0) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Set-CIPPUserJITAdmin -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter {
            $RunNow -and $Task.Name -like 'JIT Admin (enable)*' -and $Task.PostExecution.Webhook -and $Task.PostExecution.Push -and -not $Task.PostExecution.Email
        }
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter { -not $RunNow -and $Task.Name -like 'JIT Admin (RemoveRoles)*' }
    }

    It 'keeps a future start as a scheduled enable task plus the disable task' {
        $Response = Invoke-ExecJITAdmin -Request (New-Request -StartOffsetSeconds 3600) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Set-CIPPUserJITAdmin -Times 0
        Should -Invoke Set-CIPPUserJITAdminProperties -Times 1
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter { -not $RunNow -and $Task.Name -like 'JIT Admin (enable)*' }
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter { -not $RunNow -and $Task.Name -like 'JIT Admin (RemoveRoles)*' }
        Should -Invoke Add-CIPPScheduledTask -Times 2
    }
}
