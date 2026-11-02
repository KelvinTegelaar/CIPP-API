BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $altEmail, $APIName, $TargetUser, $PushMessage, $Url) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPJITAdminApprovalNotification.ps1')

    $ApprovalRequest = [pscustomobject]@{
        RowKey        = '11111111-1111-1111-1111-111111111111'
        Tenant        = 'contoso.com'
        TargetUser    = 'jit@contoso.com'
        RoleNames     = 'Application Administrator'
        StartDate     = '1791590400'
        EndDate       = '1791676800'
        RequestedBy   = 'tech@msp.com'
        ApproverRoles = '["superadmin"]'
    }
}

Describe 'Send-CIPPJITAdminApprovalNotification push' {
    BeforeEach {
        $script:OriginalNg = $env:CIPPNG
        Mock Send-CIPPAlert { }
        Mock Write-LogMessage { throw $message }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'allowedUsers' } {
            [pscustomobject]@{ RowKey = 'boss@msp.com'; Roles = '["superadmin"]' }
            [pscustomobject]@{ RowKey = 'tech@msp.com'; Roles = '["superadmin"]' }
            [pscustomobject]@{ RowKey = 'viewer@msp.com'; Roles = '["readonly"]' }
        }
    }
    AfterEach { $env:CIPPNG = $script:OriginalNg }

    It 'sends no push outside CIPP-NG' {
        $env:CIPPNG = $null
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Requested'
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Rejected' -Note 'No'
        Should -Invoke Send-CIPPAlert -Times 0 -ParameterFilter { $Type -eq 'push' }
    }

    It 'pushes a new request to approvers other than the requester on CIPP-NG' {
        $env:CIPPNG = 'true'
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Requested'
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' -and $TargetUser -eq 'boss@msp.com' }
    }

    It 'pushes a decision to the requester on CIPP-NG' {
        $env:CIPPNG = 'true'
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Approved'
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'push' -and $TargetUser -eq 'tech@msp.com' }
    }
}

Describe 'Send-CIPPJITAdminApprovalNotification email' {
    BeforeEach {
        $script:OriginalNg = $env:CIPPNG
        $env:CIPPNG = $null
        Mock Send-CIPPAlert { }
        Mock Write-LogMessage { throw $message }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'allowedUsers' } {
            [pscustomobject]@{ RowKey = 'boss@msp.com'; Roles = '["superadmin"]' }
            [pscustomobject]@{ RowKey = 'tech@msp.com'; Roles = '["superadmin"]' }
            [pscustomobject]@{ RowKey = 'viewer@msp.com'; Roles = '["readonly"]' }
        }
    }
    AfterEach { $env:CIPPNG = $script:OriginalNg }

    It 'emails a new request to approvers other than the requester, on any platform' {
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Requested'
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'email' -and $altEmail -eq 'boss@msp.com' -and $HTMLContent -like '*jit@contoso.com*' }
        Should -Invoke Send-CIPPAlert -Times 0 -ParameterFilter { $Type -eq 'push' }
    }

    It 'emails a decision to the requester' {
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Rejected' -Note 'No'
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'email' -and $altEmail -eq 'tech@msp.com' }
    }

    It 'keeps the global notification email next to the approver emails' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'SchedulerConfig' } { [pscustomobject]@{ email = 'ops@msp.com' } }
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Requested'
        Should -Invoke Send-CIPPAlert -Times 2 -Exactly -ParameterFilter { $Type -eq 'email' }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'email' -and -not $altEmail }
        Should -Invoke Send-CIPPAlert -Times 1 -ParameterFilter { $Type -eq 'email' -and $altEmail -eq 'boss@msp.com' }
    }

    It 'sends nothing to approvers when no CIPP user holds an approver role' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'allowedUsers' } { }
        Send-CIPPJITAdminApprovalNotification -ApprovalRequest $ApprovalRequest -Status 'Requested'
        Should -Invoke Send-CIPPAlert -Times 0 -ParameterFilter { $Type -eq 'email' }
    }
}
