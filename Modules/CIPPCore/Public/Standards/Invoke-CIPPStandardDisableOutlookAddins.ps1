function Invoke-CIPPStandardDisableOutlookAddins {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RoleAssignmentPolicy' | Where-Object { $_.IsDefault -eq $true }
    $Roles = @('My Custom Apps', 'My Marketplace Apps', 'My ReadWriteMailbox Apps')
    $RolesToRemove = foreach ($Role in $Roles) {
        if ($CurrentInfo.AssignedRoles -contains $Role) {
            $Role
        }
    }

    if ($Settings.remediate) {
        if ($RolesToRemove) {
            $Errors = [System.Collections.Generic.List[string]]::new()
            
            foreach ($Role in $RolesToRemove) {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ManagementRoleAssignment' -cmdparams @{ RoleAssignee = $CurrentInfo.Identity; Role = $Role } | ForEach-Object {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Remove-ManagementRoleAssignment' -cmdparams @{ Identity = $_.Guid; Confirm = $false } -UseSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled Outlook add-in role: $Role" -sev Debug
                    }
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Outlook add-in role: $Role Error: $($_.exception.message)" -sev Error
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

    if ($Settings.alert) {
        if ($RolesToRemove) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from installing Outlook add-ins.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are disabled from installing Outlook add-ins.' -sev Info
        }
    }
    if ($Settings.report) {
        if ($RolesToRemove) { $State = $false } else { $State = $true }
        Add-CIPPBPAField -FieldName 'DisabledOutlookAddins' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}