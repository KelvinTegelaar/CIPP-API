BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPJITAdminApprovalRequirement.ps1')

    $GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    function New-Settings {
        param([bool]$RequireApproval = $true, [string]$TriggerRoles = '[]')
        [pscustomobject]@{ RequireApproval = $RequireApproval; ApprovalTriggerRoles = $TriggerRoles; ApproverRoles = '["admin","Approvers"]'; RequiredApprovals = 2 }
    }
}

Describe 'Get-CIPPJITAdminApprovalRequirement' {
    It 'requires nothing when approval is off' {
        Mock Get-CIPPAzDataTableEntity { New-Settings -RequireApproval $false }
        Get-CIPPJITAdminApprovalRequirement -Roles @($GlobalAdmin) | Should -BeNullOrEmpty
    }

    It 'requires approval for every request when no trigger roles are set' {
        Mock Get-CIPPAzDataTableEntity { New-Settings }
        $Requirement = Get-CIPPJITAdminApprovalRequirement -Roles @()
        $Requirement.RequiredApprovals | Should -Be 2
        $Requirement.ApproverRoles | Should -Be @('admin', 'Approvers')
    }

    It 'only requires approval when a trigger role is requested' {
        Mock Get-CIPPAzDataTableEntity { New-Settings -TriggerRoles "[{`"label`":`"Global Administrator`",`"value`":`"$GlobalAdmin`"}]" }
        Get-CIPPJITAdminApprovalRequirement -Roles @('other-role') | Should -BeNullOrEmpty
        Get-CIPPJITAdminApprovalRequirement -Roles @('other-role', $GlobalAdmin) | Should -Not -BeNullOrEmpty
    }
}
