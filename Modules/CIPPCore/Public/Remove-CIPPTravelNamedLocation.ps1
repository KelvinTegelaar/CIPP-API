function Remove-CIPPTravelNamedLocation {
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        [string]$PolicyName,
        [string]$LocationId,
        $Headers
    )
    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$LocationId" -tenantid $TenantFilter -type DELETE -body '' -asApp $true
        Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelNamedLocation' -message "Deleted Named Location $LocationId for policy '$PolicyName'" -Sev 'Info' -tenant $TenantFilter
        return "Successfully deleted Named Location for policy '$PolicyName'"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API 'Remove-CIPPTravelNamedLocation' -message "Failed to delete Named Location for '$PolicyName': $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Failed to delete Named Location: $($ErrorMessage.NormalizedError)"
    }
}
