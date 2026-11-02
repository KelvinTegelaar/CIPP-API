function Remove-CIPPTravelPolicy {
    <#
    .SYNOPSIS
    Removes a temporary travel conditional access policy and its named location.

    .DESCRIPTION
    Deletes the conditional access policy and the country named location that were created by
    New-CIPPTravelPolicy. Both objects are located by their shared display name. The policy is
    deleted first because the named location cannot be removed while a policy still references it.

    .PARAMETER Headers
    The headers to include in the request, typically containing authentication tokens. Supplied automatically by the API.

    .PARAMETER TenantFilter
    The tenant identifier to filter the request.

    .PARAMETER PolicyName
    The display name shared by the conditional access policy and the named location.

    .PARAMETER APIName
    The name of the API operation being performed. Defaults to 'Remove-CIPPTravelPolicy'.
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$PolicyName,
        [string]$APIName = 'Remove-CIPPTravelPolicy'
    )
    try {
        $Results = [System.Collections.Generic.List[string]]::new()

        $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$select=id,displayName&$top=999' -tenantid $TenantFilter -asApp $true | Where-Object { $_.displayName -eq $PolicyName }
        foreach ($Policy in $Policies) {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($Policy.id)" -type DELETE -tenantid $TenantFilter -asApp $true
            $Results.Add("Deleted temporary travel policy '$PolicyName'.")
        }
        if (!$Policies) {
            $Results.Add("No conditional access policy named '$PolicyName' was found, it may have been removed already.")
        }

        $Locations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$select=id,displayName&$top=999' -tenantid $TenantFilter -asApp $true | Where-Object { $_.displayName -eq $PolicyName }
        foreach ($Location in $Locations) {
            # Deleting a named location right after deleting the policy that references it can fail
            # while the policy deletion propagates, so retry a few times.
            $RetryCount = 0
            $MaxRetryCount = 5
            $Deleted = $false
            do {
                try {
                    $null = Set-CIPPNamedLocation -NamedLocationId $Location.id -TenantFilter $TenantFilter -Change 'delete' -APIName $APIName -Headers $Headers
                    $Deleted = $true
                } catch {
                    $RetryCount++
                    if ($RetryCount -ge $MaxRetryCount) { throw }
                    Write-Information "Named location '$PolicyName' could not be deleted yet, will retry..."
                    Start-Sleep -Seconds 5
                }
            } while (!$Deleted -and $RetryCount -lt $MaxRetryCount)
            $Results.Add("Deleted temporary travel named location '$PolicyName'.")
        }
        if (!$Locations) {
            $Results.Add("No named location named '$PolicyName' was found, it may have been removed already.")
        }

        $Result = $Results -join ' '
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove temporary travel policy '$PolicyName': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
