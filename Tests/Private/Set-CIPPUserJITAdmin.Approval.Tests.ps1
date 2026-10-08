BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CIPPJITAdminApprovalRequirement { param($Roles) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPUserJITAdmin.ps1')

    $RequestId = '11111111-1111-1111-1111-111111111111'
    $Role = '62e90394-69f5-4237-9190-012177145e10'
    $Grant = @{ TenantFilter = 'contoso.com'; User = @{ UserPrincipalName = 'jit@contoso.com' }; Roles = @($Role); Action = 'AddRoles' }
}

Describe 'Set-CIPPUserJITAdmin approval guard' {
    BeforeEach {
        Mock Get-CIPPJITAdminApprovalRequirement { [pscustomobject]@{ ApproverRoles = @('admin'); RequiredApprovals = 1 } }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ State = 'Completed'; Tenant = 'contoso.com'; TargetUser = 'jit@contoso.com'; RoleIds = "[`"$Role`"]"; GroupIds = '[]' }
        }
    }

    It 'blocks an elevation with no approved request' {
        { Set-CIPPUserJITAdmin @Grant -WhatIf } | Should -Throw '*no approved JIT Admin request*'
    }

    It 'blocks an elevation that adds roles beyond the approved request' {
        $Wider = $Grant.Clone(); $Wider.Roles = @($Role, 'other-role')
        { Set-CIPPUserJITAdmin @Wider -ApprovalRequestId $RequestId -WhatIf } | Should -Throw '*no approved JIT Admin request*'
    }

    It 'blocks an elevation for a different user than the approved request' {
        $OtherUser = $Grant.Clone(); $OtherUser.User = @{ UserPrincipalName = 'other@contoso.com' }
        { Set-CIPPUserJITAdmin @OtherUser -ApprovalRequestId $RequestId -WhatIf } | Should -Throw '*no approved JIT Admin request*'
    }

    It 'allows an elevation covered by a provisioned request' {
        { Set-CIPPUserJITAdmin @Grant -ApprovalRequestId $RequestId -WhatIf } | Should -Not -Throw
    }

    It 'does not gate removals or elevations when no approval is required' {
        Mock Get-CIPPJITAdminApprovalRequirement { }
        { Set-CIPPUserJITAdmin @Grant -WhatIf } | Should -Not -Throw
        Mock Get-CIPPJITAdminApprovalRequirement { [pscustomobject]@{ ApproverRoles = @('admin'); RequiredApprovals = 1 } }
        $Removal = $Grant.Clone(); $Removal.Action = 'RemoveRoles'
        { Set-CIPPUserJITAdmin @Removal -WhatIf } | Should -Not -Throw
    }
}
