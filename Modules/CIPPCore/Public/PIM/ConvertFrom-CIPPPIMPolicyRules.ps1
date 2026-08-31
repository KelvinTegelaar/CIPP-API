function ConvertFrom-CIPPPIMPolicyRules {
    <#
    .SYNOPSIS
        Reads a tenant's PIM role management policy rules into the canonical settings shape.

    .DESCRIPTION
        Inverse of ConvertTo-CIPPPIMPolicyRules. Lets a live policy be graded against the secure
        floor (Test-CIPPPIMRoleSettingsFloor) and summarised (Get-CIPPPIMPolicySummary) with the
        same code that handles templates.

        A $null duration means the rule does not require expiration, i.e. permanent
        assignments/eligibilities are allowed by that policy.

    .PARAMETER Rules
        The policy's rules (unifiedRoleManagementPolicyRule collection), from
        policies/roleManagementPolicies/{id}/rules or the RoleManagementPolicies cache.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Rules
    )

    $ById = @{}
    foreach ($Rule in @($Rules)) {
        if ($Rule.id) { $ById[$Rule.id] = $Rule }
    }

    function Get-ExpirationDuration {
        param([string]$RuleId)
        $Rule = $ById[$RuleId]
        if (-not $Rule) { return $null }
        if ($Rule.isExpirationRequired -ne $true) { return $null }
        return $Rule.maximumDuration
    }

    function Get-EnabledRules {
        param([string]$RuleId)
        $Rule = $ById[$RuleId]
        if (-not $Rule) { return @() }
        return @($Rule.enabledRules)
    }

    $ActivationEnablement = Get-EnabledRules 'Enablement_EndUser_Assignment'
    $AuthContext = $ById['AuthenticationContext_EndUser_Assignment']
    $Approval = $ById['Approval_EndUser_Assignment']
    $AdminEnablement = Get-EnabledRules 'Enablement_Admin_Assignment'
    $Notification = $ById['Notification_Admin_EndUser_Assignment']

    $ActivationRequires = if ($AuthContext -and $AuthContext.isEnabled -eq $true) {
        'AuthenticationContext'
    } elseif ($ActivationEnablement -contains 'MultiFactorAuthentication') {
        'MFA'
    } else {
        'None'
    }

    $Approvers = @()
    if ($Approval -and $Approval.setting -and $Approval.setting.approvalStages) {
        foreach ($Stage in @($Approval.setting.approvalStages)) {
            foreach ($Approver in @($Stage.primaryApprovers)) {
                $Approvers += ($Approver.description ?? $Approver.groupId ?? $Approver.userId)
            }
        }
    }

    [PSCustomObject]@{
        activationMaxDuration                 = Get-ExpirationDuration 'Expiration_EndUser_Assignment'
        activationRequires                    = $ActivationRequires
        authenticationContextClaimValue       = if ($AuthContext) { $AuthContext.claimValue } else { '' }
        activationRequiresJustification       = ($ActivationEnablement -contains 'Justification')
        activationRequiresTicket              = ($ActivationEnablement -contains 'Ticketing')
        activationRequiresApproval            = [bool]($Approval -and $Approval.setting -and $Approval.setting.isApprovalRequired -eq $true)
        approvers                             = ($Approvers | Where-Object { $_ }) -join ', '
        eligibilityMaxDuration                = Get-ExpirationDuration 'Expiration_Admin_Eligibility'
        activeAssignmentMaxDuration           = Get-ExpirationDuration 'Expiration_Admin_Assignment'
        activeAssignmentRequiresMfa           = ($AdminEnablement -contains 'MultiFactorAuthentication')
        activeAssignmentRequiresJustification = ($AdminEnablement -contains 'Justification')
        notificationRecipients                = if ($Notification) { @($Notification.notificationRecipients) -join ', ' } else { '' }
        notificationLevel                     = if ($Notification) { $Notification.notificationLevel } else { 'All' }
    }
}
