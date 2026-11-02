function Set-CIPPCopyGroupMembers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Headers,
        [string]$UserId,
        [string]$CopyFromId,
        [string]$TenantFilter,
        [string]$APIName = 'Copy User Groups',
        [switch]$ExchangeOnly
    )

    $Requests = @(
        @{
            id     = 'User'
            url    = 'users/{0}' -f $UserId
            method = 'GET'
        }
        @{
            id     = 'UserMembership'
            url    = 'users/{0}/memberOf' -f $UserId
            method = 'GET'
        }
        @{
            id     = 'CopyFromMembership'
            url    = 'users/{0}/memberOf' -f $CopyFromId
            method = 'GET'
        }
    )
    $Results = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter
    $User = ($Results | Where-Object { $_.id -eq 'User' }).body
    $CurrentMemberships = ($Results | Where-Object { $_.id -eq 'UserMembership' }).body.value
    $CopyFromMemberships = ($Results | Where-Object { $_.id -eq 'CopyFromMembership' }).body.value

    # Write-Information ($Results | ConvertTo-Json -Depth 10) # For debugging

    $ODataBind = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}' -f $User.id
    $AddMemberBody = @{
        '@odata.id' = $ODataBind
    } | ConvertTo-Json -Compress

    $Success = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()
    $Skipped = [System.Collections.Generic.List[object]]::new()

    # Not every membership can or should be copied, but a group that is quietly dropped looks
    # identical to one the copy simply missed - so say which ones were left out and why. The three
    # policy skips are reported per group because they are the surprising ones; groups the target
    # already belongs to are summarised on one line instead, since a copy between two long-standing
    # colleagues would otherwise bury the real outcome under dozens of unremarkable lines.
    $AlreadyMember = [System.Collections.Generic.List[string]]::new()
    $Memberships = [System.Collections.Generic.List[object]]::new()

    foreach ($Group in @($CopyFromMemberships | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' })) {
        $GroupLabel = if ([string]::IsNullOrWhiteSpace($Group.displayName)) { $Group.id } else { $Group.displayName }
        if ($Group.groupTypes -contains 'DynamicMembership') {
            $Skipped.Add("Skipped $($GroupLabel): its membership is set by a dynamic rule, so members cannot be added directly.")
        } elseif ($Group.onPremisesSyncEnabled -eq $true) {
            $Skipped.Add("Skipped $($GroupLabel): it is synced from on-premises Active Directory and has to be changed there.")
        } elseif ($Group.visibility -eq 'Public') {
            $Skipped.Add("Skipped $($GroupLabel): it is a public group, which users can join themselves.")
        } elseif ($CurrentMemberships.id -contains $Group.id) {
            $AlreadyMember.Add($GroupLabel)
        } else {
            $Memberships.Add($Group)
        }
    }

    if ($AlreadyMember.Count -gt 0) {
        $Plural = if ($AlreadyMember.Count -eq 1) { 'group' } else { 'groups' }
        $Skipped.Add("Already a member of $($AlreadyMember.Count) $($Plural), left unchanged: $($AlreadyMember -join ', ').")
    }

    foreach ($SkipMessage in $Skipped) {
        Write-LogMessage -headers $Headers -API $APIName -message $SkipMessage -Sev 'Info' -tenant $TenantFilter
    }

    $ScheduleExchangeGroupTask = $false
    foreach ($MailGroup in $Memberships) {
        try {
            if ($PSCmdlet.ShouldProcess($MailGroup.displayName, "Add $UserId to group")) {
                if ($MailGroup.MailEnabled -and $MailGroup.ResourceProvisioningOptions -notcontains 'Team' -and $MailGroup.groupTypes -notcontains 'Unified') {
                    $Params = @{ Identity = $MailGroup.id; Member = $UserId; BypassSecurityGroupManagerCheck = $true }
                    try {
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                    } catch {
                        if ($_.Exception.Message -match 'Ex94914C|Microsoft.Exchange.Configuration.Tasks.ManagementObjectNotFoundException') {
                            if (($User.assignedLicenses | Measure-Object).Count -gt 0 -and !$ExchangeOnly.IsPresent) {
                                $ScheduleExchangeGroupTask = $true
                            } else {
                                throw $_
                            }
                        } else {
                            throw $_
                        }
                    }
                } elseif (!$ExchangeOnly.IsPresent) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($MailGroup.id)/members/`$ref" -tenantid $TenantFilter -body $AddMemberBody -Verbose
                }
            }

            if ($ScheduleExchangeGroupTask) {
                $TaskBody = [PSCustomObject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Copy Exchange Group Membership: $UserId from $CopyFromId"
                    Command       = @{
                        value = 'Set-CIPPCopyGroupMembers'
                    }
                    Parameters    = [PSCustomObject]@{
                        UserId       = $UserId
                        CopyFromId   = $CopyFromId
                        TenantFilter = $TenantFilter
                        ExchangeOnly = $true
                    }
                    ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(5) - (Get-Date '1/1/1970')).TotalSeconds
                    PostExecution = @{
                        Webhook = $false
                        Email   = $false
                        PSA     = $false
                    }
                }
                Add-CIPPScheduledTask -Task $TaskBody -hidden $false
                $Errors.Add("We've scheduled a task to add $UserId to the Exchange group $($MailGroup.displayName)") | Out-Null
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Added $UserId to group $($MailGroup.displayName)" -Sev 'Info' -tenant $TenantFilter
                $Success.Add("Added user to group: $($MailGroup.displayName)") | Out-Null
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Errors.Add("We've failed to add the group $($MailGroup.displayName): $($ErrorMessage.NormalizedError)") | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Group adding failed for group $($_.displayName):  $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    $Results = [PSCustomObject]@{
        'Success' = $Success
        'Error'   = $Errors
        'Skipped' = $Skipped
    }

    return @($Results)
}
