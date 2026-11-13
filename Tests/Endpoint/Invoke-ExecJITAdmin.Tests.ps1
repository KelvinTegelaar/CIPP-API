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
    function Get-CIPPJITAdminApprovalRequirement { param($Roles, $TenantFilter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($TableName, $Entity) }
    function Send-CIPPJITAdminApprovalNotification { param($ApprovalRequest, $Status, $Note, $Results) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body) }
    function New-PwPushLink { param($Payload) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
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
        Should -Invoke Get-CIPPJITAdminApprovalRequirement -ParameterFilter { $TenantFilter -eq 'contoso.com' }
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

Describe 'Invoke-ExecJITAdmin request validation and allow-list' {
    BeforeAll {
        $GroupId = 'aaaaaaaa-0000-0000-0000-000000000001'
        $Restricted = { [pscustomobject]@{ Restricted = $true; AllowedRoleIds = @('62e90394-69f5-4237-9190-012177145e10') } }
    }
    BeforeEach {
        Mock Add-CIPPScheduledTask { }
        Mock Set-CIPPUserJITAdminProperties { }
        Mock Start-Sleep { }
        Mock New-GraphPostRequest { [pscustomobject]@{ temporaryAccessPass = 'tap' } }
    }

    It 'refuses a group id that is not a GUID' {
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName GroupMemberships -NotePropertyValue @([pscustomobject]@{ value = "x/../../directoryRoles(roleTemplateId='62e90394-69f5-4237-9190-012177145e10')" })
        $Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'refuses a role id that is not a GUID' {
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body.AdminRoles = @([pscustomobject]@{ value = '62e90394-69f5-4237-9190-012177145e10/x' })
        $Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'refuses variants of a role outside the allow-list for a restricted caller' {
        Mock Get-CIPPJITAdminAllowedRoles $Restricted
        foreach ($Variant in @('E8611AB8-C189-46E8-94E1-60213AB1F814', '{e8611ab8-c189-46e8-94e1-60213ab1f814}')) {
            $Request = New-Request -StartOffsetSeconds 0
            $Request.Body.AdminRoles = @([pscustomobject]@{ value = $Variant })
            (Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 403
        }
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'refuses a role-assignable group for a restricted caller' {
        Mock Get-CIPPJITAdminAllowedRoles $Restricted
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $GroupId; displayName = 'Tier0'; isAssignableToRole = $true } }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName GroupMemberships -NotePropertyValue @([pscustomobject]@{ value = $GroupId })
        $Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 403
        $Response.Body.Results[0] | Should -BeLike '*Tier0*'
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'refuses a group it cannot look up for a restricted caller' {
        Mock Get-CIPPJITAdminAllowedRoles $Restricted
        Mock New-GraphGetRequest { throw 'Forbidden' }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName GroupMemberships -NotePropertyValue @([pscustomobject]@{ value = $GroupId })
        (Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 403
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'allows an ordinary group for a restricted caller when Graph reports isAssignableToRole as <Name>' -ForEach @(
        @{ Name = 'false'; Flag = $false }
        @{ Name = 'null'; Flag = $null }
    ) {
        Mock Get-CIPPJITAdminAllowedRoles $Restricted
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $GroupId; displayName = 'Helpdesk'; isAssignableToRole = $Flag } }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName GroupMemberships -NotePropertyValue @([pscustomobject]@{ value = $GroupId })
        (Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter { $RunNow -and $Task.Parameters.Groups -contains $GroupId }
    }

    It 'refuses a temporary access pass for an existing user for a restricted caller' {
        Mock Get-CIPPJITAdminAllowedRoles $Restricted
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName UseTAP -NotePropertyValue $true
        (Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 403
        Should -Invoke New-GraphPostRequest -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'leaves an unrestricted caller free to use any group and a TAP for an existing user' {
        Mock New-GraphGetRequest { }
        $Request = New-Request -StartOffsetSeconds 0
        $Request.Body | Add-Member -NotePropertyName GroupMemberships -NotePropertyValue @([pscustomobject]@{ value = $GroupId })
        $Request.Body | Add-Member -NotePropertyName UseTAP -NotePropertyValue $true
        (Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 200
        Should -Invoke New-GraphPostRequest -Times 1
        Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like '*/groups/*' }
    }
}
