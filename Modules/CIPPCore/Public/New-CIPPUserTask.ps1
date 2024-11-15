function New-CIPPUserTask {
    [CmdletBinding()]
    param (
        $userobj,
        $APIName = 'New User Task',
        $ExecutingUser
    )
    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        $CreationResults = New-CIPPUser -userobj $UserObj -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
        $results.add('Created New User.')
        $results.add("Username: $($CreationResults.username)")
        $results.add("Password: $($CreationResults.password)")
    } catch {
        $results.add("Failed to create user. $($_.Exception.Message)" )
        return @{'Results' = $results }
    }

    try {
        $licenses = (($UserObj | Select-Object 'License_*').psobject.properties | Where-Object { $_.value -EQ $true }).name -replace 'License_', ''
        if ($licenses) {
            $LicenseResults = Set-CIPPUserLicense -userid $CreationResults.username -TenantFilter $UserObj.tenantID -Licenses $licenses
            $Results.Add($LicenseResults)
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantID) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($Userobj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -user $CreationResults.username -Aliases ($UserObj.AddedAliases -split '\s') -UserprincipalName $CreationResults.Username -TenantFilter $UserObj.tenantID -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
            $results.add($AliasResults)
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantID) -message "Failed to create the Aliases. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to create the Aliases: $($_.Exception.Message)")
    }
    if ($userobj.CopyFrom -ne '') {
        $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -CopyFromId $userObj.CopyFrom -UserID $CreationResults.Username -TenantFilter $UserObj.tenantID
        $CopyFrom.Success | ForEach-Object { $results.Add($_) }
        $CopyFrom.Error | ForEach-Object { $results.Add($_) }
    }

    if ($userobj.setManager) {
        $ManagerResult = Set-CIPPManager -user $CreationResults.username -Manager $userObj.setManager.value -TenantFilter $UserObj.tenantID -APIName 'Set Manager' -ExecutingUser $request.headers.'x-ms-client-principal'
        $results.add($ManagerResult)
    }

    return @{
        Results  = $results
        username = $CreationResults.username
        password = $CreationResults.password
        CopyFrom = $CopyFrom
    }
}

