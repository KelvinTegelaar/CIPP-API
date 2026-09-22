function Invoke-CIPPStandardPIMRoleSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PIMRoleSettings
    .SYNOPSIS
        (Label) PIM Role Settings Template
    .DESCRIPTION
        (Helptext) Deploys a Privileged Identity Management role settings template to the tenant: activation limits, MFA or authentication context, justification, approval, eligibility and active-assignment expiry and notification rules for the roles the template covers. Templates cannot weaken settings below CIPP's secure floor.
        (DocsDescription) Deploys a Privileged Identity Management role settings template to the tenant. The template defines, for a set of roles, the maximum activation duration, whether activation requires MFA or an authentication context, justification, ticket and approval requirements, the maximum lifetime of eligible and active assignments, and additional notification recipients. Templates are validated against CIPP's secure floor (activation within 24 hours with MFA or an authentication context and a justification; eligible and active assignments must expire within a year; active assignments require a justification) and are refused, not adjusted, when they fall below it. Requires Entra ID P2.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2026-08-23
        TAG
        EXECUTIVETEXT
            Enforces consistent Privileged Identity Management settings so that administrator roles can only be used for a limited time, after strong authentication and with a recorded reason. This keeps standing administrative access to a minimum and makes every use of privilege visible and accountable.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"TemplateList","multiple":false,"required":true,"creatable":false,"label":"Select PIM Role Settings Template","api":{"url":"/api/ListPIMRoleSettingsTemplates","labelField":"templateName","valueField":"GUID","queryKey":"ListPIMRoleSettingsTemplates","showRefresh":true,"templateView":{"title":"PIM Role Settings Template"}}}
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyRoleManagementPolicyRule
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TemplateId = $Settings.TemplateList.value ?? $Settings.TemplateList
    $FieldName = "standards.PIMRoleSettings.$TemplateId"

    $TestResult = Test-CIPPStandardLicense -StandardName 'PIMRoleSettings' -TenantFilter $Tenant -Preset EntraP2
    if ($TestResult -eq $false) {
        Set-CIPPStandardsCompareField -FieldName $FieldName -FieldValue 'This tenant does not have the Entra ID P2 license required for Privileged Identity Management.' -LicenseAvailable $false -TenantFilter $Tenant
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($TemplateId)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PIMRoleSettings: no template selected.' -sev Error
        return
    }

    # Load and re-validate the template: a template row edited by hand must not be able to push a
    # tenant below the floor, so the check runs at deploy time as well as at save time.
    $Table = Get-CippTable -tablename 'templates'
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $TemplateId -Type String
    $TemplateRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'PIMRoleSettingsTemplate' and (RowKey eq '$SafeId' or GUID eq '$SafeId')" | Select-Object -First 1
    if (-not $TemplateRow) {
        $Message = "PIM role settings template $TemplateId could not be found."
        Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Error
        Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = $Message } -ExpectedValue @{ Differences = @() } -TenantFilter $Tenant
        return
    }
    $Template = $TemplateRow.JSON | ConvertFrom-Json -Depth 100
    $TemplateSettings = ConvertTo-CIPPPIMRoleSettings -InputObject $Template.settings
    $Floor = Test-CIPPPIMRoleSettingsFloor -Settings $TemplateSettings
    if (-not $Floor.Valid) {
        $Message = "PIM role settings template '$($Template.templateName)' is below the secure floor and was not applied: $($Floor.Errors -join ' ')"
        Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Error
        Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = $Message } -ExpectedValue @{ Differences = @() } -TenantFilter $Tenant
        return
    }
    foreach ($Warning in $Floor.Warnings) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIM role settings template '$($Template.templateName)': $Warning" -sev Warning
    }

    try {
        $Policies = @(Get-CIPPPIMRolePolicies -TenantFilter $Tenant)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not read PIM role policies: $ErrorMessage" -sev Error
        return
    }
    if ($Policies.Count -eq 0) {
        $Message = 'No PIM role management policies were returned. Privileged Identity Management may not be onboarded in this tenant yet; open PIM once in the Entra admin center.'
        Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Warning
        Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = $Message } -ExpectedValue @{ Differences = @() } -TenantFilter $Tenant
        return
    }

    # Role names for messages; PIM's roleDefinitionId is the template id for built-in roles.
    $RoleNames = @{}
    foreach ($Entry in (Get-CIPPPrivilegedRoleTemplateIds -WithNames)) { $RoleNames[$Entry.Id] = $Entry.DisplayName }
    try {
        foreach ($Definition in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,templateId,displayName' -tenantid $Tenant)) {
            if ($Definition.id) { $RoleNames[$Definition.id] = $Definition.displayName }
            if ($Definition.templateId) { $RoleNames[$Definition.templateId] = $Definition.displayName }
        }
    } catch {
        Write-Information "Could not list role definitions for $Tenant`: $($_.Exception.Message)"
    }

    $RoleIds = switch ("$($Template.roleScope)") {
        'AllRoles' { @($Policies.RoleDefinitionId) }
        'Custom' { @($Template.roles | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ }) }
        default { @(Get-CIPPPrivilegedRoleTemplateIds -Set Privileged) }
    }

    # Approvers are stored by name/UPN so a template works across tenants; resolve them here.
    $ResolvedApprovers = @()
    if ($TemplateSettings.activationRequiresApproval) {
        foreach ($Approver in @("$($TemplateSettings.approvers)" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            try {
                if ($Approver -match '@') {
                    $SafeUpn = ConvertTo-CIPPODataFilterValue -Value $Approver -Type String
                    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$SafeUpn'&`$select=id,userPrincipalName" -tenantid $Tenant | Select-Object -First 1
                    if ($User) { $ResolvedApprovers += [ordered]@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $User.id; description = $User.userPrincipalName } }
                    else { Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIMRoleSettings: approver '$Approver' was not found." -sev Warning }
                } else {
                    $SafeName = ConvertTo-CIPPODataFilterValue -Value $Approver -Type String
                    $Group = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$SafeName'&`$select=id,displayName" -tenantid $Tenant | Select-Object -First 1
                    if ($Group) { $ResolvedApprovers += [ordered]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $Group.id; description = $Group.displayName } }
                    else { Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIMRoleSettings: approver group '$Approver' was not found." -sev Warning }
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIMRoleSettings: could not resolve approver '$Approver': $($_.Exception.Message)" -sev Warning
            }
        }
        if ($ResolvedApprovers.Count -eq 0) {
            $Message = "PIM role settings template '$($Template.templateName)' requires approval but none of its approvers exist in this tenant; the template was not applied."
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Error
            Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = $Message } -ExpectedValue @{ Differences = @() } -TenantFilter $Tenant
            return
        }
    }

    function Get-RoleDifferences {
        param($PolicySet)
        $PolicyByRole = @{}
        foreach ($Policy in $PolicySet) { $PolicyByRole[$Policy.RoleDefinitionId] = $Policy }
        $Found = [System.Collections.Generic.List[object]]::new()
        foreach ($RoleId in $RoleIds) {
            $RoleLabel = $RoleNames[$RoleId] ?? $RoleId
            $Policy = $PolicyByRole[$RoleId]
            if (-not $Policy) {
                $Found.Add([PSCustomObject]@{ Role = $RoleLabel; RoleDefinitionId = $RoleId; Policy = $null; Desired = $null; Differences = @([PSCustomObject]@{ Role = $RoleLabel; Rule = '-'; Property = 'policy'; Expected = 'present'; Current = 'no PIM policy for this role' }) })
                continue
            }
            $Desired = ConvertTo-CIPPPIMPolicyRules -Settings $TemplateSettings -CurrentRules $Policy.Rules -ResolvedApprovers $ResolvedApprovers
            $Differences = @(Compare-CIPPPIMRoleSettings -DesiredRules $Desired -CurrentRules $Policy.Rules -RoleName $RoleLabel)
            $Found.Add([PSCustomObject]@{ Role = $RoleLabel; RoleDefinitionId = $RoleId; Policy = $Policy; Desired = $Desired; Differences = $Differences })
        }
        return $Found
    }

    $RoleStates = Get-RoleDifferences -PolicySet $Policies
    $Drifted = @($RoleStates | Where-Object { $_.Differences.Count -gt 0 })

    if ($Settings.remediate -eq $true) {
        if ($Drifted.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIM role settings already match template '$($Template.templateName)' for $($RoleStates.Count) role(s)." -sev Info
        } else {
            foreach ($State in $Drifted) {
                if (-not $State.Policy) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIMRoleSettings: no PIM policy exists for $($State.Role); cannot apply the template to it." -sev Warning
                    continue
                }
                $null = Set-CIPPPIMRoleSettings -TenantFilter $Tenant -PolicyId $State.Policy.PolicyId -DesiredRules $State.Desired -CurrentRules $State.Policy.Rules -RoleName $State.Role -APIName 'Standards'
            }
            # Re-read so the report reflects the post-remediation state.
            try {
                $RoleStates = Get-RoleDifferences -PolicySet @(Get-CIPPPIMRolePolicies -TenantFilter $Tenant)
                $Drifted = @($RoleStates | Where-Object { $_.Differences.Count -gt 0 })
            } catch {
                Write-Information "Could not re-read PIM policies after remediation: $($_.Exception.Message)"
            }
        }
    }

    $DifferenceText = @($Drifted | ForEach-Object { $State = $_; $State.Differences | ForEach-Object { "$($State.Role): $($_.Rule).$($_.Property) expected '$($_.Expected)', found '$($_.Current)'" } })

    if ($Settings.alert -eq $true) {
        if ($Drifted.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIM role settings match template '$($Template.templateName)'." -sev Info
        } else {
            Write-StandardsAlert -message "PIM role settings for $($Drifted.Count) role(s) differ from template '$($Template.templateName)'" -object @{ Template = $Template.templateName; Differences = $DifferenceText } -tenant $Tenant -standardName 'PIMRoleSettings' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "PIM role settings for $($Drifted.Count) role(s) differ from template '$($Template.templateName)'." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = @($DifferenceText) } -ExpectedValue @{ Differences = @() } -TenantFilter $Tenant
    }
}
