function New-CIPPUserTask {
    [CmdletBinding()]
    param (
        $UserObj,
        $APIName = 'New User Task',
        $TenantFilter,
        $Headers
    )
    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        $CreationResults = New-CIPPUser -UserObj $UserObj -APIName $APIName -Headers $Headers
        $Results.Add('Created New User.')
        $Results.Add("Username: $($CreationResults.Username)")
        $Results.Add("Password: $($CreationResults.Password)")
    } catch {
        $Results.Add("Failed to create user. $($_.Exception.Message)" )
        return @{'Results' = $Results }
    }

    try {
        if ($UserObj.licenses.value) {
            $LicenseResults = Set-CIPPUserLicense -UserId $CreationResults.Username -TenantFilter $UserObj.tenantFilter -AddLicenses $UserObj.licenses.value -Headers $Headers
            $Results.Add($LicenseResults)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($UserObj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -user $CreationResults.Username -Aliases ($UserObj.AddedAliases -split '\s') -UserprincipalName $CreationResults.Username -TenantFilter $UserObj.tenantFilter -APIName $APIName -Headers $Headers
            $Results.Add($AliasResults)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to create the Aliases. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to create the Aliases: $($_.Exception.Message)")
    }
    if ($UserObj.copyFrom.value) {
        Write-Host "Copying from $($UserObj.copyFrom.value)"
        $CopyFrom = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $UserObj.copyFrom.value -UserID $CreationResults.Username -TenantFilter $UserObj.tenantFilter
        $CopyFrom.Success | ForEach-Object { $Results.Add($_) }
        $CopyFrom.Error | ForEach-Object { $Results.Add($_) }
    }

    if ($UserObj.setManager) {
        $ManagerResult = Set-CIPPManager -user $CreationResults.Username -Manager $UserObj.setManager.value -TenantFilter $UserObj.tenantFilter -APIName 'Set Manager' -Headers $Headers
        $Results.Add($ManagerResult)
    }

    if ($UserObj.setSponsor) {
        $SponsorResult = Set-CIPPManager -user $CreationResults.Username -Manager $UserObj.setSponsor.value -TenantFilter $UserObj.tenantFilter -APIName 'Set Sponsor' -Headers $Headers
        $Results.Add($SponsorResult)
    }

    return @{
        Results  = $Results
        Username = $CreationResults.Username
        Password = $CreationResults.Password
        CopyFrom = $CopyFrom
    }
}
