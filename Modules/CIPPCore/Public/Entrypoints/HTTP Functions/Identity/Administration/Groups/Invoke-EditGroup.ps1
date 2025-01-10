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
    $GroupType = $userobj.groupId.addedFields.groupType ? $userobj.groupId.addedFields.groupType : $userobj.groupType
    $GroupName = $userobj.groupName ? $userobj.groupName : $userobj.groupId.addedFields.groupName
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $AddMembers = ($userobj.Addmember).value ?? $userobj.AddMember
    $userobj.groupId = $userobj.groupId.value ?? $userobj.groupId

    $TenantId = $userobj.tenantid ?? $userobj.tenantFilter

    if ($AddMembers) {
        $AddMembers | ForEach-Object {
            try {
                $member = $_
                if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
                $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($member)" -tenantid $TenantId).id
                $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $TenantId -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)" -tenantid $TenantId -type patch -body $addmemberbody -Verbose
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Added $member to $($GroupName) group" -Sev 'Info'
                $null = $results.add("Success. $member has been added to $($GroupName)")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to add member $member to $($GroupName). Error:$($_.Exception.Message)" -Sev 'Error'
                $null = $results.add("Failed to add member $member to $($GroupName): $($_.Exception.Message)")
            }
        }

    }
    $AddContacts = ($userobj.AddContact).value

    if ($AddContacts) {
        $AddContacts | ForEach-Object {
            try {
                $member = $_
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $TenantId -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                    Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message "Added $member to $($GroupName) group" -Sev 'Info'
                    $null = $results.add("Success. $member has been added to $($GroupName)")
                } else {
                    Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message 'You cannot add a contact to a security group' -Sev 'Error'
                    $null = $results.add('You cannot add a contact to a security group')
                }
            } catch {
                $null = $results.add("Failed to add member $member to $($GroupName): $($_.Exception.Message)")
            }
        }

    }

    $RemoveContact = ($userobj.RemoveContact).value
    try {
        if ($RemoveContact) {
            $RemoveContact | ForEach-Object {
                $member = $_
                if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member ; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $TenantId -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantId)
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $TenantId -type DELETE
                }
                Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message "Removed $member from $($GroupName) group" -Sev 'Info'
                $null = $results.add("Success. Member $member has been removed from $($GroupName)")
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to remove $RemoveContact from $($GroupName). Error:$($_.Exception.Message)" -Sev 'Error'
        $null = $results.add("Could not remove $RemoveContact from $($GroupName). $($_.Exception.Message)")
    }


    $RemoveMembers = ($userobj.Removemember).value
    try {
        if ($RemoveMembers) {
            $RemoveMembers | ForEach-Object {
                $member = $_
                if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member ; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $TenantId -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantId)
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $TenantId -type DELETE
                }
                Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message "Removed $member from $($GroupName) group" -Sev 'Info'
                $null = $results.add("Success. Member $member has been removed from $($GroupName)")
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to remove $RemoveMembers from $($GroupName). Error:$($_.Exception.Message)" -Sev 'Error'
        $null = $results.add("Could not remove $RemoveMembers from $($GroupName). $($_.Exception.Message)")
    }

    $AddOwners = $userobj.Addowner.value
    try {
        if ($AddOwners) {
            $AddOwners | ForEach-Object {
                try {
                    $ID = 'https://graph.microsoft.com/beta/users/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantId).id
                    Write-Host $ID
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/`$ref" -tenantid $TenantId -type POST -body ('{"@odata.id": "' + $ID + '"}')
                    Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message "Added owner $_ to $($GroupName) group" -Sev 'Info'
                    $null = $results.add("Success. $_ has been added $($GroupName)")
                } catch {
                    $null = $results.add("Failed to add owner $_ to $($GroupName): Error:$($_.Exception.Message)")
                }
            }

        }

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $TenantId -API $APINAME -message "Add member API failed. $($_.Exception.Message)" -Sev 'Error'
    }

    $RemoveOwners = ($userobj.RemoveOwner).value
    try {
        if ($RemoveOwners) {
            $RemoveOwners | ForEach-Object {
                try {
                    $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantId)
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/$($MemberInfo.id)/`$ref" -tenantid $TenantId -type DELETE
                    Write-LogMessage -API $APINAME -tenant $TenantId -user $request.headers.'x-ms-client-principal' -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev 'Info'
                    $null = $results.add("Success. Member $_ has been removed from $($GroupName)")
                } catch {
                    $null = $results.add("Failed to remove $_ from $($GroupName): $($_.Exception.Message)")
                }
            }
        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to remove $RemoveMembers from $($GroupName). Error:$($_.Exception.Message)" -Sev 'Error'
        $body = $results.add("Could not remove $RemoveMembers from $($GroupName). $($_.Exception.Message)")
    }

    if ($userobj.allowExternal -eq 'true') {
        try {
            Set-CIPPGroupAuthentication -ID $userobj.mail -GroupType $GroupType -tenantFilter $TenantId -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
            $body = $results.add("Allowed external senders to send to $($userobj.mail).")
        } catch {
            $body = $results.add("Failed to allow external senders to send to $($userobj.mail).")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to allow external senders for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }

    }

    if ($userobj.sendCopies -eq 'true') {
        try {
            $Params = @{ Identity = $userobj.Groupid; subscriptionEnabled = $true; AutoSubscribeNewMembers = $true }
            New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $params -useSystemMailbox $true

            $MemberParams = @{ Identity = $userobj.Groupid; LinkType = 'members' }
            $Members = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-UnifiedGrouplinks' -cmdParams $MemberParams

            $MemberSmtpAddresses = $Members | ForEach-Object { $_.PrimarySmtpAddress }

            $subscriberParams = @{ Identity = $userobj.Groupid; LinkType = 'subscribers'; Links = @($MemberSmtpAddresses) }
            New-ExoRequest -tenantid $TenantId -cmdlet 'Add-UnifiedGrouplinks' -cmdParams $subscriberParams -Anchor $userobj.mail


            $body = $results.add("Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled.")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled." -Sev 'Info'
        } catch {
            $body = $results.add("Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail).")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $TenantId -message "Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }
    }

    $body = @{'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
