function Set-CIPPCAExclusion {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $ExclusionType,
        $UserID,
        $PolicyId, 
        $executingUser
    )
    try {
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter
        if ($ExclusionType -eq 'add') {
            $NewExclusions = [pscustomobject]@{
                conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        excludeUsers = @($CheckExististing.conditions.users.excludeUsers + $UserID)
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions 
            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON
            
        } 

        if ($ExclusionType -eq 'remove') {
            $NewExclusions = [pscustomobject]@{
                conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        excludeUsers = @($CheckExististing.conditions.users.excludeUsers | Where-Object { $_ -ne $UserID })
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions 
            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON 
        }

        Write-LogMessage -user $executingUser -API 'Set-CIPPConditionalAccessExclusion' -message "Successfully performed $($ExclusionType) user from policy $($PolicyId)" -Sev 'Info' -tenant $TenantFilter
    } catch {
        Write-LogMessage -user $executingUser -API 'Set-CIPPConditionalAccessExclusion' -message "Failed to $($ExclusionType) user from policy $($PolicyId): $_" -Sev 'Error' -tenant $TenantFilter
    }
}