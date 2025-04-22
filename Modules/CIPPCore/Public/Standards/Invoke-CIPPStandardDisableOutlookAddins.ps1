function Invoke-CIPPStandardDisableOutlookAddins {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableOutlookAddins
    .SYNOPSIS
        (Label) Disable users from installing add-ins in Outlook
    .DESCRIPTION
        (Helptext) Disables the ability for users to install add-ins in Outlook. This is to prevent users from installing malicious add-ins.
        (DocsDescription) Disables users from being able to install add-ins in Outlook. Only admins are able to approve add-ins for the users. This is done to reduce the threat surface for data exfiltration.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
            "exo_outlookaddins"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-02-05
        POWERSHELLEQUIVALENT
            Get-ManagementRoleAssignment \| Remove-ManagementRoleAssignment
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableOutlookAddins'

    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RoleAssignmentPolicy' | Where-Object { $_.IsDefault -eq $true }
    $Roles = @('My Custom Apps', 'My Marketplace Apps', 'My ReadWriteMailbox Apps')
    $RolesToRemove = foreach ($Role in $Roles) {
        if ($CurrentInfo.AssignedRoles -contains $Role) {
            $Role
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($RolesToRemove) {
            $Errors = [System.Collections.Generic.List[string]]::new()

            foreach ($Role in $RolesToRemove) {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ManagementRoleAssignment' -cmdParams @{ RoleAssignee = $CurrentInfo.Identity; Role = $Role } | ForEach-Object {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Remove-ManagementRoleAssignment' -cmdParams @{ Identity = $_.Guid; Confirm = $false } -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled Outlook add-in role: $Role" -sev Debug
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Outlook add-in role: $Role Error: $ErrorMessage" -sev Error
                    $Errors.Add($Role)
                }
            }

            if ($Errors.Count -gt 0) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from installing Outlook add-ins. Roles: $($Errors -join ', ')" -sev Error
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled users from installing Outlook add-ins. Roles removed: $($RolesToRemove -join ', ')" -sev Info
                $RolesToRemove = $null
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users installing Outlook add-ins already disabled' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($RolesToRemove) {
            Write-StandardsAlert -message 'Users are not disabled from installing Outlook add-ins.' -object @{ AllowedApps = $RolesToRemove -join ',' } -tenant $tenant -standardName 'DisableOutlookAddins' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from installing Outlook add-ins.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are disabled from installing Outlook add-ins.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $State = if ($RolesToRemove) { $false } else { $true }
        $StateForCompare = if ($RolesToRemove) { @{ AllowedApps = $RolesToRemove } } else { $true }
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableOutlookAddins' -FieldValue $StateForCompare -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisabledOutlookAddins' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}
