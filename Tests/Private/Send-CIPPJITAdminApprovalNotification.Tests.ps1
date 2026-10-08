BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $APIName, $TargetUser, $PushMessage, $Url) }
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
