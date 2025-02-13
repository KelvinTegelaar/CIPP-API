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

    Write-Information ($Results | ConvertTo-Json -Depth 10)

    $ODataBind = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}' -f $User.id
    $AddMemberBody = @{
        '@odata.id' = $ODataBind
    } | ConvertTo-Json -Compress

    $Success = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()
    $Memberships = $CopyFromMemberships | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' -and $_.groupTypes -notcontains 'DynamicMembership' -and $_.onPremisesSyncEnabled -ne $true -and $_.visibility -ne 'Public' -and $CurrentMemberships.id -notcontains $_.id }
    $ScheduleExchangeGroupTask = $false
    foreach ($MailGroup in $Memberships) {
        try {
            if ($PSCmdlet.ShouldProcess($MailGroup.displayName, "Add $UserId to group")) {
                if ($MailGroup.MailEnabled -and $Mailgroup.ResourceProvisioningOptions -notcontains 'Team' -and $MailGroup.groupTypes -notcontains 'Unified') {
                    $Params = @{ Identity = $MailGroup.mailNickname; Member = $UserId; BypassSecurityGroupManagerCheck = $true }
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
    }

    return @($Results)
}
