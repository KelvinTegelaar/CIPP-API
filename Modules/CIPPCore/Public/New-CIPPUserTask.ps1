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

    # Add to groups
    if ($UserObj.AddToGroups) {
        $ExoGroupTypes = @('Distribution list', 'Distribution List', 'Mail-Enabled Security', 'distributionList', 'security')
        $UserObj.AddToGroups | ForEach-Object {
            $Group = $_
            $GroupType = $Group.addedFields.groupType
            try {
                $AddMemberResult = Add-CIPPGroupMember -Headers $Headers -GroupType $GroupType -GroupId $Group.value -Member @($CreationResults.Username) -TenantFilter $UserObj.tenantFilter
                $Results.Add($AddMemberResult)
            } catch {
                # EXO group adds frequently fail right after user creation due to Exchange directory replication lag.
                # Schedule a delayed retry so the user lands in the group automatically once EXO sees the recipient.
                if ($GroupType -in $ExoGroupTypes) {
                    try {
                        $TaskBody = [PSCustomObject]@{
                            TenantFilter  = $UserObj.tenantFilter
                            Name          = "Retry Add Group Member: $($CreationResults.Username) -> $($Group.label)"
                            Command       = @{ value = 'Add-CIPPGroupMember' }
                            Parameters    = [PSCustomObject]@{
                                GroupType    = $GroupType
                                GroupId      = $Group.value
                                Member       = @($CreationResults.Username)
                                TenantFilter = $UserObj.tenantFilter
                                APIName      = 'Add Group Member (Retry)'
                            }
                            ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
                            PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
                        }
                        $null = Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers -DisallowDuplicateName $true
                        $Results.Add("Could not add $($CreationResults.Username) to $($Group.label) yet (Exchange replication delay). A retry has been scheduled in 15 minutes.")
                    } catch {
                        $Results.Add("Failed to add to group $($Group.label): $_")
                    }
                } else {
                    $Results.Add("Failed to add to group $($Group.label): $_")
                }
            }
        }
    }

    if ($UserObj.setManager) {
        $ManagerResults = Set-CIPPManager -Users $CreationResults.Username -Manager $UserObj.setManager.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($ManagerResults.Result)
    }

    if ($UserObj.setSponsor) {
        $SponsorResults = Set-CIPPSponsor -Users $CreationResults.Username -Sponsor $UserObj.setSponsor.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($SponsorResults.Result)
    }

    return @{
        Results  = $Results
        Username = $CreationResults.Username
        Password = $CreationResults.Password
        CopyFrom = $CopyFrom
        User     = $CreationResults.User
    }
}
