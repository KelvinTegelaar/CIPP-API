function Remove-CIPPGroup {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $GroupType,
        $ID,
        $DisplayName,
        $APIName = "Remove Group",
        $TenantFilter
    )

    try {
        if ($GroupType -eq "Distribution List" -or $GroupType -eq "Mail-Enabled Security") {
            New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-DistributionGroup" -cmdParams @{Identity = $id; BypassSecurityGroupManagerCheck = $true } -useSystemMailbox $true
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($DisplayName) Deleted" -Sev "Info"
            return "Successfully Deleted $($GroupType) group $($DisplayName)"
        }
        elseif ($GroupType -eq "Microsoft 365" -or $GroupType -eq "Security") {
            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$($ID)" -tenantid $TenantFilter -type Delete -verbose
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($DisplayName) Deleted" -Sev "Info"
            return "Successfully Deleted $($GroupType) group $($DisplayName)"
        }

    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not delete $DisplayName" -Sev "Error" -tenant $TenantFilter
        return "Could not delete $DisplayName. Error: $($_.Exception.Message)"
    }
}



