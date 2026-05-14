function Remove-CIPPTravelCAPolicy {
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        [string]$PolicyName,
        [string[]]$Users,
        $Headers
    )
    try {
        # Find and delete the travel CA policy by display name
        $Policies = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies?`$filter=displayName eq '$PolicyName'&`$select=id,displayName" `
            -tenantid $TenantFilter -asApp $true
        if (-not $Policies) {
            Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                -message "Travel policy '$PolicyName' not found, may already be deleted" `
                -Sev 'Info' -tenant $TenantFilter
        } else {
            foreach ($Policy in $Policies) {
                $null = New-GraphPOSTRequest `
                    -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($Policy.id)" `
                    -tenantid $TenantFilter -type DELETE -body '' -asApp $true
                Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                    -message "Deleted travel CA policy: $($Policy.displayName)" `
                    -Sev 'Info' -tenant $TenantFilter
            }
        }

        # Remove users from TravelingUsers group only if not active in other travel policies
        if ($Users -and $Users.Count -gt 0) {
            $ActivePolicies = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies?`$filter=startsWith(displayName,'TravelPolicy_')&`$select=id,displayName,conditions" `
                -tenantid $TenantFilter -asApp $true
            $TravelGroup = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq 'TravelingUsers'&`$select=id" `
                -tenantid $TenantFilter -asApp $true -ComplexFilter
            $TravelGroupId = $TravelGroup[0].id
            foreach ($User in $Users) {
                # Check if user is in any other active travel policy
                $StillActive = $ActivePolicies | Where-Object {
                    $_.displayName -ne $PolicyName -and
                    $_.conditions.users.includeUsers -contains $User
                }
                if (-not $StillActive) {
                    try {
                        $null = New-GraphPOSTRequest `
                            -uri "https://graph.microsoft.com/beta/groups/$TravelGroupId/members/$User/`$ref" `
                            -tenantid $TenantFilter -type DELETE -body '' -asApp $true
                        Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                            -message "Removed user $User from TravelingUsers (no other active travel policies)" `
                            -Sev 'Info' -tenant $TenantFilter
                    } catch {
                        Write-Information "Could not remove user $User from group (may already be removed): $($_.Exception.Message)"
                    }
                } else {
                    Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                        -message "User $User kept in TravelingUsers - still active in: $($StillActive.displayName -join ', ')" `
                        -Sev 'Info' -tenant $TenantFilter
                }
            }
        }

        return "Successfully deleted travel policy '$PolicyName' and associated resources"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
            -message "Failed to delete travel policy '$PolicyName': $($ErrorMessage.NormalizedError)" `
            -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Failed to delete travel policy: $($ErrorMessage.NormalizedError)"
    }
}
