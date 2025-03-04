function Remove-CIPPGroup {
    [CmdletBinding()]
    param (
        $Headers,
        $GroupType,
        $ID,
        $DisplayName,
        $APIName = 'Remove Group',
        $TenantFilter
    )

    try {
        if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DistributionGroup' -cmdParams @{Identity = $ID; BypassSecurityGroupManagerCheck = $true } -useSystemMailbox $true
            Write-LogMessage -headers $Headers -API $APINAME -tenant $($TenantFilter) -message "$($DisplayName) Deleted" -Sev 'Info'
            return "Successfully Deleted $($GroupType) group $($DisplayName)"

        } elseif ($GroupType -eq 'Microsoft 365' -or $GroupType -eq 'Security') {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$($ID)" -tenantid $TenantFilter -type Delete -verbose
            Write-LogMessage -headers $Headers -API $APINAME -tenant $($TenantFilter) -message "$($DisplayName) Deleted" -Sev 'Info'
            return "Successfully Deleted $($GroupType) group $($DisplayName)"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Could not delete $DisplayName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}



