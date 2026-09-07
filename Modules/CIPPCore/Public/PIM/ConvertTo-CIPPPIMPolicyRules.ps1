function ConvertTo-CIPPPIMPolicyRules {
    <#
    .SYNOPSIS
        Turns canonical PIM role settings into the policy rule objects Graph expects.

    .DESCRIPTION
        Produces only the rules CIPP manages, each carrying '@odata.type', 'id' and the 'target'
        copied from the tenant's current rule (Graph requires the target on PATCH). Rules CIPP does
        not manage (requestor/approver notifications, ticketing for admin assignment, ...) are left
        untouched in the tenant.

        Callers validate the settings against the floor BEFORE calling this; it does not re-check.

    .PARAMETER Settings
        Canonical settings (ConvertTo-CIPPPIMRoleSettings).

    .PARAMETER CurrentRules
        The role's current rules, used for the 'target' and to keep unmanaged approval-stage
        details when approval is switched off.

    .PARAMETER ResolvedApprovers
        Approver objects already resolved in the tenant:
        @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = '...'; description = 'Name' } or
        @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = '...'; description = 'upn' }.
        Required when activationRequiresApproval is true.

    .OUTPUTS
        Ordered hashtables, one per managed rule.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $CurrentRules,

        [array]$ResolvedApprovers = @()
    )

    $ById = @{}
    foreach ($Rule in @($CurrentRules)) {
        if ($Rule.id) { $ById[$Rule.id] = $Rule }
    }

    function Get-Target {
        param([string]$RuleId)
        $Rule = $ById[$RuleId]
        if ($Rule -and $Rule.target) { return $Rule.target }
        return $null
    }

    function ConvertTo-Rule {
        param([string]$Id, [string]$Type, [System.Collections.IDictionary]$Properties)
        $Rule = [ordered]@{
            '@odata.type' = $Type
            id            = $Id
        }
        $Target = Get-Target $Id
        if ($Target) { $Rule.target = $Target }
        foreach ($Key in $Properties.Keys) { $Rule[$Key] = $Properties[$Key] }
        return $Rule
    }

    $ExpirationType = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'
    $EnablementType = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
    $AuthContextType = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
    $ApprovalType = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'
    $NotificationType = '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule'

    $Desired = [System.Collections.Generic.List[object]]::new()

    # Activation (end user)
    $Desired.Add((ConvertTo-Rule -Id 'Expiration_EndUser_Assignment' -Type $ExpirationType -Properties ([ordered]@{
                    isExpirationRequired = $true
                    maximumDuration      = $Settings.activationMaxDuration
                })))

    $ActivationEnabled = [System.Collections.Generic.List[string]]::new()
    if ("$($Settings.activationRequires)" -eq 'MFA') { $ActivationEnabled.Add('MultiFactorAuthentication') }
    if ($Settings.activationRequiresJustification) { $ActivationEnabled.Add('Justification') }
    if ($Settings.activationRequiresTicket) { $ActivationEnabled.Add('Ticketing') }
    $Desired.Add((ConvertTo-Rule -Id 'Enablement_EndUser_Assignment' -Type $EnablementType -Properties ([ordered]@{
                    enabledRules = @($ActivationEnabled)
                })))

    $UseAuthContext = ("$($Settings.activationRequires)" -eq 'AuthenticationContext')
    $AuthContextProps = [ordered]@{ isEnabled = $UseAuthContext }
    if ($UseAuthContext) { $AuthContextProps.claimValue = $Settings.authenticationContextClaimValue }
    $Desired.Add((ConvertTo-Rule -Id 'AuthenticationContext_EndUser_Assignment' -Type $AuthContextType -Properties $AuthContextProps))

    $CurrentApproval = $ById['Approval_EndUser_Assignment']
    if ($Settings.activationRequiresApproval) {
        $Desired.Add((ConvertTo-Rule -Id 'Approval_EndUser_Assignment' -Type $ApprovalType -Properties ([ordered]@{
                        setting = [ordered]@{
                            isApprovalRequired               = $true
                            isApprovalRequiredForExtension   = $false
                            isRequestorJustificationRequired = $true
                            approvalMode                     = 'SingleStage'
                            approvalStages                   = @(
                                [ordered]@{
                                    approvalStageTimeOutInDays      = 1
                                    isApproverJustificationRequired = $true
                                    escalationTimeInMinutes         = 0
                                    primaryApprovers                = @($ResolvedApprovers)
                                    isEscalationEnabled             = $false
                                    escalationApprovers             = @()
                                }
                            )
                        }
                    })))
    } else {
        # Keep the tenant's stage configuration; only flip the requirement off.
        $Setting = [ordered]@{ isApprovalRequired = $false }
        if ($CurrentApproval -and $CurrentApproval.setting) {
            foreach ($Property in $CurrentApproval.setting.PSObject.Properties) {
                if ($Property.Name -ne 'isApprovalRequired') { $Setting[$Property.Name] = $Property.Value }
            }
        }
        $Desired.Add((ConvertTo-Rule -Id 'Approval_EndUser_Assignment' -Type $ApprovalType -Properties ([ordered]@{ setting = $Setting })))
    }

    # Admin eligibility / assignment
    $Desired.Add((ConvertTo-Rule -Id 'Expiration_Admin_Eligibility' -Type $ExpirationType -Properties ([ordered]@{
                    isExpirationRequired = $true
                    maximumDuration      = $Settings.eligibilityMaxDuration
                })))
    $Desired.Add((ConvertTo-Rule -Id 'Expiration_Admin_Assignment' -Type $ExpirationType -Properties ([ordered]@{
                    isExpirationRequired = $true
                    maximumDuration      = $Settings.activeAssignmentMaxDuration
                })))

    $AdminEnabled = [System.Collections.Generic.List[string]]::new()
    if ($Settings.activeAssignmentRequiresMfa) { $AdminEnabled.Add('MultiFactorAuthentication') }
    if ($Settings.activeAssignmentRequiresJustification) { $AdminEnabled.Add('Justification') }
    $Desired.Add((ConvertTo-Rule -Id 'Enablement_Admin_Assignment' -Type $EnablementType -Properties ([ordered]@{
                    enabledRules = @($AdminEnabled)
                })))

    # Notifications to additional admins - only managed when the template names recipients.
    $Recipients = @("$($Settings.notificationRecipients)" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Recipients.Count -gt 0) {
        foreach ($NotificationId in @('Notification_Admin_Admin_Eligibility', 'Notification_Admin_Admin_Assignment', 'Notification_Admin_EndUser_Assignment')) {
            $Desired.Add((ConvertTo-Rule -Id $NotificationId -Type $NotificationType -Properties ([ordered]@{
                            notificationType           = 'Email'
                            recipientType              = 'Admin'
                            notificationLevel          = $Settings.notificationLevel
                            isDefaultRecipientsEnabled = $true
                            notificationRecipients     = @($Recipients)
                        })))
        }
    }

    return @($Desired)
}
