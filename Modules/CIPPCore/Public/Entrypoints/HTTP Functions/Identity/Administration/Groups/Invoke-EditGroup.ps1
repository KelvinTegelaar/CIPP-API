using namespace System.Net

Function Invoke-EditGroup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.ArrayList]@()
    $userobj = $Request.body
    $GroupType = $userobj.groupType -join ','

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $AddMembers = ($userobj.Addmember).value
    if ($AddMembers) {
        $AddMembers | ForEach-Object {
            try {
                $member = $_

                if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
                $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($member)" -tenantid $Userobj.tenantid).id
                $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -Verbose
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Added $member to $($userobj.groupName) group" -Sev 'Info'
                $null = $results.add("Success. $member has been added to $($userobj.groupName)")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to add member $member to $($userobj.groupName). Error:$($_.Exception.Message)" -Sev 'Error'
                $null = $results.add("Failed to add member $member to $($userobj.groupName): $($_.Exception.Message)")
            }
        }

    }
    $AddContacts = ($userobj.AddContacts).value

    if ($AddContacts) {
        $AddContacts | ForEach-Object {
            try {
                $member = $_
                if ($userobj.groupType -eq 'Distribution list' -or $userobj.groupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                    Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Added $member to $($userobj.groupName) group" -Sev 'Info'
                    $null = $results.add("Success. $member has been added to $($userobj.groupName)")
                } else {
                    Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message 'You cannot add a contact to a security group' -Sev 'Error'
                    $null = $results.add('You cannot add a contact to a security group')
                }
            } catch {
                $null = $results.add("Failed to add member $member to $($userobj.groupName): $($_.Exception.Message)")
            }
        }

    }

    $RemoveMembers = ($userobj.Removemember).value
    try {
        if ($RemoveMembers) {
            $RemoveMembers | ForEach-Object {
                $member = $_
                if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member ; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE
                }
                Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Removed $member from $($userobj.groupName) group" -Sev 'Info'
                $null = $results.add("Success. Member $member has been removed from $($userobj.groupName)")
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to remove $RemoveMembers from $($userobj.groupName). Error:$($_.Exception.Message)" -Sev 'Error'
        $null = $results.add("Could not remove $RemoveMembers from $($userobj.groupName). $($_.Exception.Message)")
    }

    $AddOwners = $userobj.Addowner.value
    try {
        if ($AddOwners) {
            $AddOwners | ForEach-Object {
                try {
                    $ID = 'https://graph.microsoft.com/beta/users/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id
                    Write-Host $ID
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/`$ref" -tenantid $Userobj.tenantid -type POST -body ('{"@odata.id": "' + $ID + '"}')
                    Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Added owner $_ to $($userobj.groupName) group" -Sev 'Info'
                    $null = $results.add("Success. $_ has been added $($userobj.groupName)")
                } catch {
                    $null = $results.add("Failed to add owner $_ to $($userobj.groupName): Error:$($_.Exception.Message)")
                }
            }

        }

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $Userobj.tenantid -API $APINAME -message "Add member API failed. $($_.Exception.Message)" -Sev 'Error'
    }

    $RemoveOwners = ($userobj.RemoveOwner).value
    try {
        if ($RemoveOwners) {
            $RemoveOwners | ForEach-Object {
                try {
                    $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE
                    Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev 'Info'
                    $null = $results.add("Success. Member $_ has been removed from $($userobj.groupName)")
                } catch {
                    $null = $results.add("Failed to remove $_ from $($userobj.groupName): $($_.Exception.Message)")
                }
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to remove $RemoveMembers from $($userobj.groupName). Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Could not remove $RemoveMembers from $($userobj.groupName). $($_.Exception.Message)")
    }

    if ($userobj.allowExternal -eq 'true') {
        try {
            Set-CIPPGroupAuthentication -ID $userobj.mail -GroupType $userobj.groupType -tenantFilter $Userobj.tenantid -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
            $body = $results.add("Allowed external senders to send to $($userobj.mail).")
        } catch {
            $body = $results.add("Failed to allow external senders to send to $($userobj.mail).")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to allow external senders for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }

    }

    if ($userobj.sendCopies -eq 'true') {
        try {
            $Params = @{ Identity = $userobj.Groupid; subscriptionEnabled = $true; AutoSubscribeNewMembers = $true }
            New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Set-UnifiedGroup' -cmdParams $params -useSystemMailbox $true

            $MemberParams = @{ Identity = $userobj.Groupid; LinkType = 'members' }
            $Members = New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Get-UnifiedGrouplinks' -cmdParams $MemberParams

            $MemberSmtpAddresses = $Members | ForEach-Object { $_.PrimarySmtpAddress }

            $subscriberParams = @{ Identity = $userobj.Groupid; LinkType = 'subscribers'; Links = @($MemberSmtpAddresses) }
            New-ExoRequest -tenantid $Userobj.tenantid -cmdlet 'Add-UnifiedGrouplinks' -cmdParams $subscriberParams -Anchor $userobj.mail


            $body = $results.add("Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled.")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled." -Sev 'Info'
        } catch {
            $body = $results.add("Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail).")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }
    }

    $body = @{'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
