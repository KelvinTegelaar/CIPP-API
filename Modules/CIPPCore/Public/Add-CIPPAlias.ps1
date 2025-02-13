function Add-CIPPAlias {
    [CmdletBinding()]
    param (
        $user,
        $Aliases,
        $UserprincipalName,
        $TenantFilter,
        $APIName = 'Set Manager',
        $Headers
    )

    try {
        foreach ($Alias in $Aliases) {
            Write-Host "Adding alias $Alias to $user"
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$user" -tenantid $TenantFilter -type 'patch' -body "{`"mail`": `"$Alias`"}" -verbose
        }
        Write-Host "Resetting primary alias to $User"
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($user)" -tenantid $TenantFilter -type 'patch' -body "{`"mail`": `"$User`"}" -verbose
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($TenantFilter) -message "Added alias $($Alias) to $($UserprincipalName)" -Sev 'Info'
        return ("Added Aliases: $($Aliases -join ',')")
    } catch {
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($TenantFilter) -message "Failed to set alias. Error:$($_.Exception.Message)" -Sev 'Error'
        throw "Failed to set alias: $($_.Exception.Message)"
    }
}

