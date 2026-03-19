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
        $Results.Add("$($_.Exception.Message)" )
        throw @{'Results' = $Results }
    }

    try {
        if ($UserObj.licenses.value) {
            # Filter out licenses with no available units
            try {
                $SubscribedSkus = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $UserObj.tenantFilter
                $FilteredLicenses = @(foreach ($LicenseId in $UserObj.licenses.value) {
                    $Sku = $SubscribedSkus | Where-Object { $_.skuId -eq $LicenseId }
                    $Available = [int]$Sku.prepaidUnits.enabled - [int]$Sku.consumedUnits
                    if ($Sku -and $Available -le 0) {
                        $null = $Results.Add("Skipped license $($Sku.skuPartNumber): no available units")
                        Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Skipped license $($Sku.skuPartNumber) for $($CreationResults.Username): no available units" -Sev 'Warn'
                    } else {
                        $LicenseId
                    }
                })
                $UserObj.licenses = [PSCustomObject]@{ value = $FilteredLicenses }
            } catch {
                Write-Warning "Failed to check available licenses: $($_.Exception.Message)"
            }
            if ($UserObj.sherwebLicense.value) {
                $null = Set-SherwebSubscription -Headers $Headers -TenantFilter $UserObj.tenantFilter -SKU $UserObj.sherwebLicense.value -Add 1
                $null = $Results.Add('Added Sherweb License, scheduling assignment')
                $taskObject = [PSCustomObject]@{
                    TenantFilter  = $UserObj.tenantFilter
                    Name          = "Assign License: $UserPrincipalName"
                    Command       = @{
                        value = 'Set-CIPPUserLicense'
                    }
                    Parameters    = [pscustomobject]@{
                        UserId      = $CreationResults.Username
                        APIName     = 'Sherweb License Assignment'
                        AddLicenses = $UserObj.licenses.value
                    }
                    ScheduledTime = 0 #right now, which is in the next 15 minutes and should cover most cases.
                    PostExecution = @{
                        Webhook = [bool]$Request.Body.PostExecution.webhook
                        Email   = [bool]$Request.Body.PostExecution.email
                        PSA     = [bool]$Request.Body.PostExecution.psa
                    }
                }
                Add-CIPPScheduledTask -Task $taskObject -hidden $false -Headers $Headers
            } else {
                $LicenseResults = Set-CIPPUserLicense -UserId $CreationResults.Username -TenantFilter $UserObj.tenantFilter -AddLicenses $UserObj.licenses.value -Headers $Headers
                $Results.Add($LicenseResults)
            }
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($UserObj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -User $CreationResults.Username -Aliases ($UserObj.AddedAliases -split '\s') -UserPrincipalName $CreationResults.Username -TenantFilter $UserObj.tenantFilter -APIName $APIName -Headers $Headers
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

    if ($UserObj.groupMemberships -and ($UserObj.groupMemberships | Measure-Object).Count -gt 0) {
        Write-Host "Adding user to $(@($UserObj.groupMemberships).Count) groups from template"
        $ODataBind = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}' -f $CreationResults.User.id
        $AddMemberBody = @{ '@odata.id' = $ODataBind } | ConvertTo-Json -Compress
        foreach ($Group in $UserObj.groupMemberships) {
            try {
                if ($Group.mailEnabled -and $Group.groupTypes -notcontains 'Unified') {
                    $Params = @{ Identity = $Group.id; Member = $CreationResults.Username; BypassSecurityGroupManagerCheck = $true }
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $Params -UseSystemMailbox $true
                } else {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($Group.id)/members/`$ref" -tenantid $UserObj.tenantFilter -body $AddMemberBody -Verbose
                }
                $Results.Add("Added user to group from template: $($Group.displayName)")
            } catch {
                $Results.Add("Failed to add to group $($Group.displayName): $($_.Exception.Message)")
            }
        }
    }

    if ($UserObj.setManager) {
        $ManagerResult = Set-CIPPManager -User $CreationResults.Username -Manager $UserObj.setManager.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($ManagerResult)
    }

    if ($UserObj.setSponsor) {
        $SponsorResult = Set-CIPPSponsor -User $CreationResults.Username -Sponsor $UserObj.setSponsor.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($SponsorResult)
    }

    return @{
        Results  = $Results
        Username = $CreationResults.Username
        Password = $CreationResults.Password
        CopyFrom = $CopyFrom
        User     = $CreationResults.User
    }
}
