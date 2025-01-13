function New-CIPPUserTask {
    [CmdletBinding()]
    param (
        $userobj,
        $APIName = 'New User Task',
        $ExecutingUser,
        $TenantFilter
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
        if ($userobj.licenses.value) {
            $LicenseResults = Set-CIPPUserLicense -UserId $CreationResults.username -TenantFilter $UserObj.tenantFilter -AddLicenses $UserObj.licenses.value
            $Results.Add($LicenseResults)
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantFilter) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($Userobj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -user $CreationResults.username -Aliases ($UserObj.AddedAliases -split '\s') -UserprincipalName $CreationResults.Username -TenantFilter $UserObj.tenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
            $results.add($AliasResults)
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantFilter) -message "Failed to create the Aliases. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to create the Aliases: $($_.Exception.Message)")
    }
    if ($userobj.copyFrom.value) {
        Write-Host "Copying from $($userObj.copyFrom.value)"
        $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -CopyFromId $userObj.copyFrom.value -UserID $CreationResults.Username -TenantFilter $UserObj.tenantFilter
        $CopyFrom.Success | ForEach-Object { $results.Add($_) }
        $CopyFrom.Error | ForEach-Object { $results.Add($_) }
    }

    if ($userobj.setManager) {
        $ManagerResult = Set-CIPPManager -user $CreationResults.username -Manager $userObj.setManager.value -TenantFilter $UserObj.tenantFilter -APIName 'Set Manager' -ExecutingUser $request.headers.'x-ms-client-principal'
        $results.add($ManagerResult)
    }

    return @{
        Results  = $results
        username = $CreationResults.username
        password = $CreationResults.password
        CopyFrom = $CopyFrom
    }
}

