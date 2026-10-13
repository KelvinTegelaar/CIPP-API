function Get-CIPPBaselinePIMRoleSettingsState {
    <#
    .SYNOPSIS
        Prepare hook for PIMRoleSettings: grades each role the template covers against its PIM policy.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Rows = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'RoleManagementPolicies')
    if ($Rows.Count -eq 0) {
        return @{ Current = $null; NoDataReason = 'no PIM role management policies were returned - Privileged Identity Management may not be onboarded in this tenant yet; open PIM once in the Entra admin center' }
    }

    $Reference = $Item.Variables.TemplateList
    $Reference = "$($Reference.value ?? $Reference)"
    if ([string]::IsNullOrWhiteSpace($Reference)) { return @{ Current = $null; NoDataReason = 'no PIM role settings template is selected'; ConfigError = $true } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value $Reference -Type String
    $Row = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'PIMRoleSettingsTemplate' and (RowKey eq '$SafeReference' or GUID eq '$SafeReference')")[0]
    $Template = $(if ($Row.JSON) { try { $Row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null; NoDataReason = "PIM role settings template $Reference could not be found"; ConfigError = $true } }

    # Re-validated at deploy time: a hand-edited template row must not push a tenant below the floor.
    $TemplateSettings = ConvertTo-CIPPPIMRoleSettings -InputObject $Template.settings
    $Floor = Test-CIPPPIMRoleSettingsFloor -Settings $TemplateSettings
    if (-not $Floor.Valid) {
        return @{ Current = $null; NoDataReason = "PIM role settings template '$($Template.templateName)' is below the secure floor and was not applied: $($Floor.Errors -join ' ')"; ConfigError = $true }
    }
    foreach ($Warning in $Floor.Warnings) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "PIM role settings template '$($Template.templateName)': $Warning" -sev Warning
    }

    $RoleNames = @{}
    foreach ($Entry in (Get-CIPPPrivilegedRoleTemplateIds -WithNames)) { $RoleNames[$Entry.Id] = $Entry.DisplayName }
    foreach ($Definition in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'RoleDefinitions')) {
        if ($Definition.id) { $RoleNames[$Definition.id] = $Definition.displayName }
        if ($Definition.templateId) { $RoleNames[$Definition.templateId] = $Definition.displayName }
    }

    $PolicyByRole = @{}
    foreach ($Policy in $Rows) { $PolicyByRole["$($Policy.roleDefinitionId)"] = $Policy }
    $RoleIds = switch ("$($Template.roleScope)") {
        'AllRoles' { @(foreach ($Policy in $Rows) { "$($Policy.roleDefinitionId)" }) }
        'Custom' { @(foreach ($Role in @($Template.roles)) { $Id = $Role.value ?? $Role; if ($Id) { "$Id" } }) }
        default { @(Get-CIPPPrivilegedRoleTemplateIds -Set Privileged) }
    }

    # Approvers are stored by name/UPN so a template works across tenants.
    $ResolvedApprovers = [System.Collections.Generic.List[object]]::new()
    if ($TemplateSettings.activationRequiresApproval) {
        $Approvers = @(foreach ($Approver in @("$($TemplateSettings.approvers)" -split '[,;]')) { $Approver = $Approver.Trim(); if ($Approver) { $Approver } })
        # Case-insensitive like the Graph eq filters they replace; first match wins.
        $UsersByUpn = @{}
        if ($Approvers -match '@') {
            foreach ($User in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users')) {
                if ($User.userPrincipalName -and -not $UsersByUpn.ContainsKey("$($User.userPrincipalName)")) { $UsersByUpn["$($User.userPrincipalName)"] = $User }
            }
        }
        $GroupsByName = @{}
        if ($Approvers -notmatch '@') {
            foreach ($Group in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')) {
                if ($Group.displayName -and -not $GroupsByName.ContainsKey("$($Group.displayName)")) { $GroupsByName["$($Group.displayName)"] = $Group }
            }
        }
        foreach ($Approver in $Approvers) {
            if ($Approver -match '@') {
                $User = $UsersByUpn[$Approver]
                if ($User) { $ResolvedApprovers.Add([ordered]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $User.id; description = $User.userPrincipalName }) }
                else { Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "PIMRoleSettings: approver '$Approver' was not found." -sev Warning }
            } else {
                $Group = $GroupsByName[$Approver]
                if ($Group) { $ResolvedApprovers.Add([ordered]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $Group.id; description = $Group.displayName }) }
                else { Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "PIMRoleSettings: approver group '$Approver' was not found." -sev Warning }
            }
        }
        if ($ResolvedApprovers.Count -eq 0) {
            return @{ Current = $null; NoDataReason = "PIM role settings template '$($Template.templateName)' requires approval but none of its approvers exist in this tenant; the template was not applied"; ConfigError = $true }
        }
    }

    $Expected = [ordered]@{}
    $CurrentState = [ordered]@{}
    $Drifted = [System.Collections.Generic.List[object]]::new()
    foreach ($RoleId in $RoleIds) {
        $RoleLabel = $RoleNames[$RoleId] ?? $RoleId
        if ($Expected.Contains($RoleLabel)) { $RoleLabel = "$RoleLabel ($RoleId)" }
        $Expected[$RoleLabel] = 'Matches template'
        $Policy = $PolicyByRole[$RoleId]
        if (-not $Policy) {
            $CurrentState[$RoleLabel] = 'No PIM policy for this role'
            $Drifted.Add([PSCustomObject]@{ Role = $RoleLabel; PolicyId = $null; Desired = $null; Rules = $null })
            continue
        }
        $Rules = @($Policy.rules)
        $Desired = @(ConvertTo-CIPPPIMPolicyRules -Settings $TemplateSettings -CurrentRules $Rules -ResolvedApprovers @($ResolvedApprovers))
        $Differences = @(Compare-CIPPPIMRoleSettings -DesiredRules $Desired -CurrentRules $Rules -RoleName $RoleLabel)
        if ($Differences.Count -eq 0) {
            $CurrentState[$RoleLabel] = 'Matches template'
            continue
        }
        $CurrentState[$RoleLabel] = @(foreach ($Difference in $Differences) { "$($Difference.Rule).$($Difference.Property) expected '$($Difference.Expected)', found '$($Difference.Current)'" }) -join '; '
        $Drifted.Add([PSCustomObject]@{ Role = $RoleLabel; PolicyId = "$($Policy.policyId)"; Desired = $Desired; Rules = $Rules })
    }

    $Current = [PSCustomObject]$CurrentState
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateName' -NotePropertyValue "$($Template.templateName)"
    $Current | Add-Member -NotePropertyName 'templateSettings' -NotePropertyValue $TemplateSettings
    $Current | Add-Member -NotePropertyName 'driftedRoles' -NotePropertyValue @($Drifted)

    @{ Expected = [PSCustomObject]$Expected; Current = $Current }
}
