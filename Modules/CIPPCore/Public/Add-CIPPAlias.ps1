function Add-CIPPAlias {
    [CmdletBinding()]
    param (
        $User,
        $Aliases,
        $UserPrincipalName,
        $TenantFilter,
        $APIName = 'Add Alias',
        $Headers
    )

    try {
        foreach ($Alias in $Aliases) {
            Write-Host "Adding alias $Alias to $User"
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$User" -tenantid $TenantFilter -type 'patch' -body "{`"mail`": `"$Alias`"}" -verbose
        }
        Write-Host "Resetting primary alias to $User"
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$User" -tenantid $TenantFilter -type 'patch' -body "{`"mail`": `"$User`"}" -verbose
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added alias $($Alias) to $($UserPrincipalName)" -Sev 'Info'
        return ("Added Aliases: $($Aliases -join ',')")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed to set alias. Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to set alias: $($ErrorMessage.NormalizedError)"
    }
}

