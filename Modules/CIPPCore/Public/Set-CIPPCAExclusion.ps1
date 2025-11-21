function Set-CIPPCAExclusion {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $ExclusionType,
        $UserID,
        $PolicyId,
        $Username,
        $Users,
        $Groups,
        $Headers
    )
    try {
        $CheckExisting = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter -AsApp $true
        if ($ExclusionType -eq 'add') {
            if ($Groups) {
                # Handle group exclusions
                $Groupnames = $Groups.addedFields.displayName
                $ExcludeGroups = [System.Collections.Generic.List[string]]::new()
                foreach ($Group in $CheckExisting.conditions.users.excludeGroups) {
                    $ExcludeGroups.Add($Group)
                }
                foreach ($Group in $Groups.value) {
                    if ($Group -and $Group -ne '' -and $ExcludeGroups -notcontains $Group) {
                        $ExcludeGroups.Add($Group)
                    }
                }
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeGroups = $ExcludeGroups
                        }
                    }
                }
            } elseif ($Users) {
                $Username = $Users.addedFields.userPrincipalName
                $ExcludeUsers = [System.Collections.Generic.List[string]]::new()
                foreach ($User in $CheckExisting.conditions.users.excludeUsers) {
                    $ExcludeUsers.Add($User)
                }
                foreach ($User in $Users.value) {
                    if ($User -and $User -ne '' -and $ExcludeUsers -notcontains $User) {
                        $ExcludeUsers.Add($User)
                    }
                }
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeUsers = $ExcludeUsers
                        }
                    }
                }
            } elseif ($UserID) {
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

            if ($Groups) {
                $Identifier = ($Groupnames -join ', ')
                $IdentifierType = 'group'
            } elseif ($Users) {
                $Identifier = ($Username -join ', ')
                $IdentifierType = 'user'
            } else {
                $Identifier = $UserID
                $IdentifierType = 'user'
            }
            if ($PSCmdlet.ShouldProcess($PolicyId, "Add exclusion for $IdentifierType $Identifier")) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExisting.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }

        if ($ExclusionType -eq 'remove') {
            if ($Groups) {
                # Handle group exclusions removal
                $GroupID = $Groups.value | Where-Object { $_ -and $_ -ne '' }
                $Groupnames = $Groups.addedFields.displayName
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeGroups = @($CheckExisting.conditions.users.excludeGroups | Where-Object { $GroupID -notcontains $_ })
                        }
                    }
                }
            } elseif ($Users) {
                $UserID = $Users.value | Where-Object { $_ -and $_ -ne '' }
                $Username = $Users.addedFields.userPrincipalName
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeUsers = @($CheckExisting.conditions.users.excludeUsers | Where-Object { $UserID -notcontains $_ })
                        }
                    }
                }
            } else {
                if ($UserID -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
                    $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter).userPrincipalName
                }
                $UserID = @($UserID)
                $NewExclusions = [pscustomobject]@{
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{
                            excludeUsers = @($CheckExisting.conditions.users.excludeUsers | Where-Object { $UserID -notcontains $_ })
                        }
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions

            if ($Groups) {
                $Identifier = ($Groupnames -join ', ')
                $IdentifierType = 'group'
            } elseif ($Users) {
                $Identifier = ($Username -join ', ')
                $IdentifierType = 'user'
            } else {
                $Identifier = $UserID
                $IdentifierType = 'user'
            }
            if ($PSCmdlet.ShouldProcess($PolicyId, "Remove exclusion for $IdentifierType $Identifier")) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExisting.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }

        if ($Groups) {
            foreach ($Group in $Groupnames) {
                "Successfully performed $($ExclusionType) exclusion for group $Group from policy $($CheckExisting.displayName)"
                Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Successfully performed $($ExclusionType) exclusion for group $Group from policy $($CheckExisting.displayName)" -Sev 'Info' -tenant $TenantFilter
            }
        } else {
            foreach ($User in $Username) {
                "Successfully performed $($ExclusionType) exclusion for $User from policy $($CheckExisting.displayName)"
                Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Successfully performed $($ExclusionType) exclusion for $User from policy $($CheckExisting.displayName)" -Sev 'Info' -tenant $TenantFilter
            }
        }
    } catch {
        if ($Groups) {
            foreach ($Group in $Groupnames) {
                "Failed to $($ExclusionType) group exclusion for $Group from policy $($CheckExisting.displayName): $($_.Exception.Message)"
                Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Failed to $($ExclusionType) group exclusion for $Group from policy $($CheckExisting.displayName): $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
            }
        } else {
            foreach ($User in $Username) {
                "Failed to $($ExclusionType) user exclusion for $User from policy $($CheckExisting.displayName): $($_.Exception.Message)"
                Write-LogMessage -headers $Headers -API 'Set-CIPPCAExclusion' -message "Failed to $($ExclusionType) user exclusion for $User from policy $($CheckExisting.displayName): $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
            }
        }
    }
}

