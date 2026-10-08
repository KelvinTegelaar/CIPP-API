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
    function Get-CIPPJITAdminApprovalRequirement { param($Roles) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($TableName, $Entity) }
    function Send-CIPPJITAdminApprovalNotification { param($ApprovalRequest, $Status, $Note, $Results) }
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

Describe 'Invoke-ExecJITAdmin approval' {
    BeforeEach {
        Mock Add-CIPPScheduledTask { }
        Mock Set-CIPPUserJITAdminProperties { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Update-AzDataTableEntity { }
        Mock Send-CIPPJITAdminApprovalNotification { }
    }

    It 'stores a pending request and notifies instead of provisioning when approval is required' {
        Mock Get-CIPPJITAdminApprovalRequirement { [pscustomobject]@{ ApproverRoles = @('admin'); RequiredApprovals = 2 } }
        $Response = Invoke-ExecJITAdmin -Request (New-Request -StartOffsetSeconds 3600) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0] | Should -BeLike '*submitted for approval*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.State -eq 'Pending' -and $Entity.RequestedBy -eq 'admin@contoso.com' -and $Entity.RequiredApprovals -eq 2 -and
            $Entity.RoleIds -eq '["62e90394-69f5-4237-9190-012177145e10"]' -and $Entity.ApproverRoles -eq '["admin"]'
        }
        Should -Invoke Send-CIPPJITAdminApprovalNotification -Times 1 -ParameterFilter { $Status -eq 'Requested' }
        Should -Invoke Add-CIPPScheduledTask -Times 0
        Should -Invoke Set-CIPPUserJITAdminProperties -Times 0
    }

    It 'provisions the stored request body, not the posted one, once approved' {
        Mock Get-CIPPJITAdminApprovalRequirement { [pscustomobject]@{ ApproverRoles = @('admin'); RequiredApprovals = 1 } }
        $Stored = New-Request -StartOffsetSeconds 0
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*JITAdminRequest*" } {
            [pscustomobject]@{ PartitionKey = 'JITAdminRequest'; RowKey = '11111111-1111-1111-1111-111111111111'; State = 'Approved'; RequestedBy = 'admin@contoso.com'; ETag = '1'; RequestBody = ($Stored.Body | ConvertTo-Json -Depth 10) }
        }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body = [pscustomobject]@{ ApprovalRequestId = '11111111-1111-1111-1111-111111111111'; AdminRoles = @([pscustomobject]@{ value = 'other-role' }) }

        $Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Update-AzDataTableEntity -ParameterFilter { $Entity.State -eq 'Completed' -and $Entity.ETag -eq '1' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter {
            $RunNow -and $Task.Parameters.ApprovalRequestId -eq '11111111-1111-1111-1111-111111111111' -and $Task.Parameters.Roles -contains '62e90394-69f5-4237-9190-012177145e10'
        }
    }

    It 'refuses a request id that is not approved' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*JITAdminRequest*" } {
            [pscustomobject]@{ PartitionKey = 'JITAdminRequest'; RowKey = '11111111-1111-1111-1111-111111111111'; State = 'Pending'; RequestedBy = 'admin@contoso.com'; ETag = '1' }
        }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName ApprovalRequestId -NotePropertyValue '11111111-1111-1111-1111-111111111111'
        $Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Update-AzDataTableEntity -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }
}
