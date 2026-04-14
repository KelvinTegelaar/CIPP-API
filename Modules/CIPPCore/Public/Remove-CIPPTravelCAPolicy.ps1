function Remove-CIPPTravelCAPolicy {
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        [string]$PolicyName,
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
            return "Policy '$PolicyName' not found or already deleted"
        }

        foreach ($Policy in $Policies) {
            $null = New-GraphPOSTRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($Policy.id)" `
                -tenantid $TenantFilter -type DELETE -body '' -asApp $true
            Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                -message "Deleted travel CA policy: $($Policy.displayName)" `
                -Sev 'Info' -tenant $TenantFilter
        }

        # Find and delete the associated country Named Location if it exists
        $CountryLocationName = $PolicyName -replace 'CIPP_TravelPolicy_', 'CIPP_Travel_'
        $CountryLocationName = "${CountryLocationName}_Countries"
        $Locations = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?`$filter=displayName eq '$CountryLocationName'&`$select=id,displayName" `
            -tenantid $TenantFilter -asApp $true

        foreach ($Loc in $Locations) {
            $null = New-GraphPOSTRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$($Loc.id)" `
                -tenantid $TenantFilter -type DELETE -body '' -asApp $true
            Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelCAPolicy' `
                -message "Deleted country Named Location: $($Loc.displayName)" `
                -Sev 'Info' -tenant $TenantFilter
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
