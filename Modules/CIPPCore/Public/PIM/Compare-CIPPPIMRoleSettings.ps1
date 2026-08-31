function Compare-CIPPPIMRoleSettings {
    <#
    .SYNOPSIS
        Lists the differences between desired PIM policy rules and a role's current rules.

    .DESCRIPTION
        Property-level comparison per managed rule so the PIMRoleSettings standard can report
        drift precisely and remediate only the rules that differ. Durations compare as timespans
        (PT480M equals PT8H); enabled-rule and recipient lists compare as sets.

    .PARAMETER DesiredRules
        Output of ConvertTo-CIPPPIMPolicyRules.

    .PARAMETER CurrentRules
        The role's current rules.

    .PARAMETER RoleName
        Display name used in the output rows.

    .OUTPUTS
        PSCustomObject rows: Role, Rule, Property, Expected, Current. Empty when compliant.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$DesiredRules,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $CurrentRules,

        [string]$RoleName = ''
    )

    $ById = @{}
    foreach ($Rule in @($CurrentRules)) {
        if ($Rule.id) { $ById[$Rule.id] = $Rule }
    }

    $Differences = [System.Collections.Generic.List[object]]::new()
    $RoleLabel = $RoleName

    function Add-Difference {
        param([string]$Rule, [string]$Property, $Expected, $Current)
        $Differences.Add([PSCustomObject]@{
                Role     = $RoleLabel
                Rule     = $Rule
                Property = $Property
                Expected = $Expected
                Current  = $Current
            })
    }

    function Test-SameDuration {
        param([string]$Expected, [string]$Current)
        if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Current)) { return ($Expected -eq $Current) }
        try {
            return ([System.Xml.XmlConvert]::ToTimeSpan($Expected) -eq [System.Xml.XmlConvert]::ToTimeSpan($Current))
        } catch {
            return ($Expected -eq $Current)
        }
    }

    function Test-SameSet {
        param($Expected, $Current)
        $ExpectedSet = @($Expected | ForEach-Object { "$_".ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
        $CurrentSet = @($Current | ForEach-Object { "$_".ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
        if ($ExpectedSet.Count -ne $CurrentSet.Count) { return $false }
        for ($i = 0; $i -lt $ExpectedSet.Count; $i++) {
            if ($ExpectedSet[$i] -ne $CurrentSet[$i]) { return $false }
        }
        return $true
    }

    function Get-ApproverKeys {
        param($Setting)
        $Keys = @()
        if ($Setting -and $Setting.approvalStages) {
            foreach ($Stage in @($Setting.approvalStages)) {
                foreach ($Approver in @($Stage.primaryApprovers)) {
                    # Property access works for both the hashtables we build and Graph's objects.
                    $Keys += ($Approver.groupId ?? $Approver.userId)
                }
            }
        }
        return @($Keys | Where-Object { $_ })
    }

    foreach ($Desired in $DesiredRules) {
        $Id = $Desired['id']
        $Current = $ById[$Id]
        if (-not $Current) {
            Add-Difference -Rule $Id -Property 'rule' -Expected 'present' -Current 'missing'
            continue
        }

        switch -Wildcard ($Desired['@odata.type']) {
            '*ExpirationRule' {
                if ([bool]$Current.isExpirationRequired -ne [bool]$Desired['isExpirationRequired']) {
                    Add-Difference -Rule $Id -Property 'isExpirationRequired' -Expected $Desired['isExpirationRequired'] -Current $Current.isExpirationRequired
                }
                if ($Desired['isExpirationRequired'] -and -not (Test-SameDuration -Expected $Desired['maximumDuration'] -Current $Current.maximumDuration)) {
                    Add-Difference -Rule $Id -Property 'maximumDuration' -Expected $Desired['maximumDuration'] -Current $Current.maximumDuration
                }
            }
            '*EnablementRule' {
                if (-not (Test-SameSet -Expected $Desired['enabledRules'] -Current $Current.enabledRules)) {
                    Add-Difference -Rule $Id -Property 'enabledRules' -Expected (@($Desired['enabledRules']) -join ', ') -Current (@($Current.enabledRules) -join ', ')
                }
            }
            '*AuthenticationContextRule' {
                if ([bool]$Current.isEnabled -ne [bool]$Desired['isEnabled']) {
                    Add-Difference -Rule $Id -Property 'isEnabled' -Expected $Desired['isEnabled'] -Current $Current.isEnabled
                }
                if ($Desired['isEnabled'] -and "$($Current.claimValue)" -ne "$($Desired['claimValue'])") {
                    Add-Difference -Rule $Id -Property 'claimValue' -Expected $Desired['claimValue'] -Current $Current.claimValue
                }
            }
            '*ApprovalRule' {
                $ExpectedRequired = [bool]$Desired['setting']['isApprovalRequired']
                $CurrentRequired = [bool]($Current.setting -and $Current.setting.isApprovalRequired -eq $true)
                if ($ExpectedRequired -ne $CurrentRequired) {
                    Add-Difference -Rule $Id -Property 'setting.isApprovalRequired' -Expected $ExpectedRequired -Current $CurrentRequired
                } elseif ($ExpectedRequired) {
                    $ExpectedApprovers = Get-ApproverKeys -Setting $Desired['setting']
                    $CurrentApprovers = Get-ApproverKeys -Setting $Current.setting
                    if (-not (Test-SameSet -Expected $ExpectedApprovers -Current $CurrentApprovers)) {
                        Add-Difference -Rule $Id -Property 'setting.approvalStages.primaryApprovers' -Expected ($ExpectedApprovers -join ', ') -Current ($CurrentApprovers -join ', ')
                    }
                }
            }
            '*NotificationRule' {
                if ("$($Current.notificationLevel)" -ne "$($Desired['notificationLevel'])") {
                    Add-Difference -Rule $Id -Property 'notificationLevel' -Expected $Desired['notificationLevel'] -Current $Current.notificationLevel
                }
                if ([bool]$Current.isDefaultRecipientsEnabled -ne [bool]$Desired['isDefaultRecipientsEnabled']) {
                    Add-Difference -Rule $Id -Property 'isDefaultRecipientsEnabled' -Expected $Desired['isDefaultRecipientsEnabled'] -Current $Current.isDefaultRecipientsEnabled
                }
                if (-not (Test-SameSet -Expected $Desired['notificationRecipients'] -Current $Current.notificationRecipients)) {
                    Add-Difference -Rule $Id -Property 'notificationRecipients' -Expected (@($Desired['notificationRecipients']) -join ', ') -Current (@($Current.notificationRecipients) -join ', ')
                }
            }
        }
    }

    return @($Differences)
}
