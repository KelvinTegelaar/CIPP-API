function Remove-CIPPTravelNamedLocation {
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        [string]$PolicyName,
        $Headers
    )
    try {
        $CountryLocationName = $PolicyName -replace 'TravelPolicy_', 'Travel_'
        $CountryLocationName = "${CountryLocationName}_Countries"
        $Locations = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?`$filter=displayName eq '$CountryLocationName'&`$select=id,displayName" `
            -tenantid $TenantFilter -asApp $true
        foreach ($Loc in $Locations) {
            $null = New-GraphPOSTRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$($Loc.id)" `
                -tenantid $TenantFilter -type DELETE -body '' -asApp $true
            Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelNamedLocation' `
                -message "Deleted country Named Location: $($Loc.displayName)" `
                -Sev 'Info' -tenant $TenantFilter
        }
        return "Successfully deleted Named Location for policy '$PolicyName'"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelNamedLocation' `
            -message "Failed to delete Named Location for '$PolicyName': $($ErrorMessage.NormalizedError)" `
            -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Failed to delete Named Location: $($ErrorMessage.NormalizedError)"
    }
}
