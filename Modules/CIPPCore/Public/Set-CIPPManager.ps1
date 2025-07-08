function Set-CIPPManager {
    [CmdletBinding()]
    param (
        $user,
        $Manager,
        $TenantFilter,
        $APIName = 'Set Manager',
        $Headers
    )

    try {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Manager)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($User)/manager/`$ref" -tenantid $TenantFilter -type PUT -body $ManagerBodyJSON -Verbose
        Write-LogMessage -headers $Headers -API $APINAME -tenant $UserObj.tenantID -message "Set $user's manager to $Manager" -Sev 'Info'
    } catch {
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($UserObj.tenantID) -message "Failed to Set Manager. Error:$($_.Exception.Message)" -Sev 'Error'
        throw "Failed to set manager: $($_.Exception.Message)"
    }
    return "Set $user's manager to $Manager"
}

