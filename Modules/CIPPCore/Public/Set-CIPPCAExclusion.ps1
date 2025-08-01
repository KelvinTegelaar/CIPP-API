function Set-CIPPCAExclusion {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $ExclusionType,
        $UserID,
        $PolicyId,
        $Username,
        $Users,
        $Headers
    )
    try {
        $CheckExisting = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter -AsApp $true
        if ($ExclusionType -eq 'add') {
            if ($Users) {
                $Username = $Users.addedFields.userPrincipalName
                $ExcludeUsers = [System.Collections.Generic.List[string]]::new()
                foreach ($User in $CheckExisting.conditions.users.excludeUsers) {
                    $ExcludeUsers.Add($User)
                }
                foreach ($User in $Users.value) {
                    if ($ExcludeUsers -notcontains $User) {
                        $ExcludeUsers.Add($User)
                    }
                }
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeUsers = $ExcludeUsers
                        }
                    }
                }
            } else {
                if ($UserID -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
                    $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter).userPrincipalName
                }
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeUsers = @($CheckExisting.conditions.users.excludeUsers + $UserID)
                        }
                    }
                }
            }

            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions
            if ($PSCmdlet.ShouldProcess($PolicyId, "Add exclusion for $UserID")) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExisting.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }

        if ($ExclusionType -eq 'remove') {
            if ($Users) {
                $UserID = $Users.value
                $Username = $Users.addedFields.userPrincipalName
            } else {
                if ($UserID -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
                    $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter).userPrincipalName
                }
                $UserID = @($UserID)
            }
            $NewExclusions = [pscustomobject]@{
                conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        excludeUsers = @($CheckExisting.conditions.users.excludeUsers | Where-Object { $UserID -notcontains $_ })
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions
            if ($PSCmdlet.ShouldProcess($PolicyId, "Remove exclusion for $UserID")) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExisting.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }

        foreach ($User in $Username) {
            "Successfully performed $($ExclusionType) exclusion for $User from policy $($CheckExisting.displayName)"
            Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Successfully performed $($ExclusionType) exclusion for $User from policy $($CheckExisting.displayName)" -Sev 'Info' -tenant $TenantFilter
        }
    } catch {
        foreach ($User in $Username) {
            "Failed to $($ExclusionType) user exclusion for $User from policy $($CheckExisting.displayName): $($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Failed to $($ExclusionType) user exclusion for $User from policy $($CheckExisting.displayName): $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
        }
    }
}

