function Set-CIPPCAExclusion {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $ExclusionType,
        $UserID,
        $PolicyId,
        $Username,
        $Headers
    )
    try {
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter -AsApp $true
        if ($ExclusionType -eq 'add') {
            $NewExclusions = [pscustomobject]@{
                conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        excludeUsers = @($CheckExististing.conditions.users.excludeUsers + $UserID)
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions
            if ($PSCmdlet.ShouldProcess($PolicyId, "Add exclusion for $UserID")) {
                New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }

        if ($ExclusionType -eq 'remove') {
            $NewExclusions = [pscustomobject]@{
                conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        excludeUsers = @($CheckExististing.conditions.users.excludeUsers | Where-Object { $_ -ne $UserID })
                    }
                }
            }
            $RawJson = ConvertTo-Json -Depth 10 -InputObject $NewExclusions
            if ($PSCmdlet.ShouldProcess($PolicyId, "Remove exclusion for $UserID")) {
                New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -AsApp $true
            }
        }
        "Successfully performed $($ExclusionType) exclusion for $username from policy $($PolicyId)"
        Write-LogMessage -headers $Headers -API 'Set-CIPPConditionalAccessExclusion' -message "Successfully performed $($ExclusionType) exclusion for $username from policy $($PolicyId)" -Sev 'Info' -tenant $TenantFilter
    } catch {
        "Failed to $($ExclusionType) user exclusion for $username from policy $($PolicyId): $($_.Exception.Message)"
        Write-LogMessage -headers $Headers -API 'Set-CIPPConditionalAccessExclusion' -message "Failed to $($ExclusionType) user exclusion for $username from policy $($PolicyId): $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
    }
}
