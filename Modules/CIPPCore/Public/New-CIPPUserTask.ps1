function New-CIPPUserTask {
    [CmdletBinding()]
    param (
        $userobj,
        $APIName = 'New User Task',
        $TenantFilter,
        $Headers
    )
    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        $CreationResults = New-CIPPUser -userobj $UserObj -APIName $APINAME -Headers $Headers
        $results.add('Created New User.')
        $results.add("Username: $($CreationResults.username)")
        $results.add("Password: $($CreationResults.password)")
    } catch {
        $results.add("Failed to create user. $($_.Exception.Message)" )
        return @{'Results' = $results }
    }

    try {
        if ($userobj.licenses.value) {
            $LicenseResults = Set-CIPPUserLicense -UserId $CreationResults.username -TenantFilter $UserObj.tenantFilter -AddLicenses $UserObj.licenses.value -Headers $Headers
            $Results.Add($LicenseResults)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($userobj.tenantFilter) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($Userobj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -user $CreationResults.username -Aliases ($UserObj.AddedAliases -split '\s') -UserprincipalName $CreationResults.Username -TenantFilter $UserObj.tenantFilter -APIName $APINAME -Headers $Headers
            $results.add($AliasResults)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($userobj.tenantFilter) -message "Failed to create the Aliases. Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Failed to create the Aliases: $($_.Exception.Message)")
    }
    if ($userobj.copyFrom.value) {
        Write-Host "Copying from $($userObj.copyFrom.value)"
        $CopyFrom = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $userObj.copyFrom.value -UserID $CreationResults.Username -TenantFilter $UserObj.tenantFilter
        $CopyFrom.Success | ForEach-Object { $results.Add($_) }
        $CopyFrom.Error | ForEach-Object { $results.Add($_) }
    }

    if ($userobj.setManager) {
        $ManagerResult = Set-CIPPManager -user $CreationResults.username -Manager $userObj.setManager.value -TenantFilter $UserObj.tenantFilter -APIName 'Set Manager' -Headers $Headers
        $results.add($ManagerResult)
    }

    return @{
        Results  = $results
        username = $CreationResults.username
        password = $CreationResults.password
        CopyFrom = $CopyFrom
    }
}

