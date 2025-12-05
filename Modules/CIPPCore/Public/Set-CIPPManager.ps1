function Set-CIPPManager {
    [CmdletBinding()]
    param (
        $User,
        $Manager,
        $TenantFilter,
        $APIName = 'Set Manager',
        $Headers
    )

    try {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Manager)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($User)/manager/`$ref" -tenantid $TenantFilter -type PUT -body $ManagerBodyJSON
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set $User's manager to $Manager" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to Set Manager. Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $_
        throw "Failed to set manager: $($ErrorMessage.NormalizedError)"
    }
    return "Set $User's manager to $Manager"
}

