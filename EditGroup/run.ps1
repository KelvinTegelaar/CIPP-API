using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()


$userobj = $Request.body

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
 
$AddMembers = ($userobj.Addmember).value
if ($AddMembers) {
    $AddMembers | ForEach-Object {
        try {
            $member = $_
            $MemberIDs = "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id 
            $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
            if ($userobj.groupType -eq "Distribution list" -or $userobj.groupType -eq "Mail-Enabled Security") {
                $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                New-ExoRequest -tenantid $Userobj.tenantid -cmdlet "Add-DistributionGroupMember" -cmdParams $params -UseSystemMailbox $true 
            }
            else {
                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -Verbose
            }
            Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Added $member to $($userobj.groupid) group" -Sev "Info"
            $body = $results.add("Success. $member has been added")
        }
        catch {
            $body = $results.add("Failed to add member $member to $($userobj.Groupid): $($_.Exception.Message)")
        }
    }

}
$AddContacts = ($userobj.AddContacts).value

if ($AddContacts) {
    $AddContacts | ForEach-Object {
        try {
            $member = $_
            if ($userobj.groupType -eq "Distribution list" -or $userobj.groupType -eq "Mail-Enabled Security") {
                $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                New-ExoRequest -tenantid $Userobj.tenantid -cmdlet "Add-DistributionGroupMember" -cmdParams $params  -UseSystemMailbox $true
                Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "Added $member to $($userobj.groupid) group" -Sev "Info"
                $body = $results.add("Success. $member has been added")
        } else {
            Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal' -message "You cannot add a contact to a security group" -Sev "Error"
            $body = $results.add("You cannot add a contact to a security group")
        }
    }
        catch {
            $body = $results.add("Failed to add member $member to $($userobj.Groupid): $($_.Exception.Message)")
        }
    }

}

$RemoveMembers = ($userobj.Removemember).value
try {
    if ($RemoveMembers) {
        $RemoveMembers | ForEach-Object { 
            $member = $_
            if ($userobj.groupType -eq "Distribution list" -or $userobj.groupType -eq "Mail-Enabled Security") {
                $Params = @{ Identity = $userobj.groupid; Member = $member ; BypassSecurityGroupManagerCheck = $true }
                New-ExoRequest -tenantid $Userobj.tenantid -cmdlet "Remove-DistributionGroupMember" -cmdParams $params  -UseSystemMailbox $true
            }
            else {
                $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE 
            }
            Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Removed $member from $($userobj.groupid) group" -Sev "Info"
            $body = $results.add("Success. Member $member has been removed")
        }  
    }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Could not remove $RemoveMembers from $($userobj.Groupid). $($_.Exception.Message)")
}

$AddOwners = $userobj.Addowner.value
try {
    if ($AddOwners) {
        $AddOwners | ForEach-Object { 
            try {
                $ID = "https://graph.microsoft.com/beta/users/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id
                Write-Host $ID
                $AddOwner = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/`$ref" -tenantid $Userobj.tenantid -type POST -body ('{"@odata.id": "' + $ID + '"}')
                Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Added owner $_ to $($userobj.groupid) group" -Sev "Info"
                $body = $results.add("Success. $_ has been added")
            }
            catch {
                $body = $results.add("Failed to add owner $_ to $($userobj.Groupid): $($_.Exception.Message)")
            }
        }

    }

}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
}

$RemoveOwners = ($userobj.RemoveOwner).value
try {
    if ($RemoveOwners) {
        $RemoveOwners | ForEach-Object { 
            try {
                $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE 
                Write-LogMessage -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev "Info"
                $body = $results.add("Success. Member $_ has been removed from $($userobj.Groupid)")
            }
            catch {
                $body = $results.add("Failed to remove $_ from $($userobj.Groupid): $($_.Exception.Message)")
            }
        }  
    }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Could not remove $RemoveMembers from $($userobj.Groupid). $($_.Exception.Message)")
}

if ($userobj.allowExternal -eq 'true') {
    try {
        if ($userobj.groupType -eq "Distribution list") {
            $Params = @{ Identity = $userobj.groupid; RequireSenderAuthenticationEnabled = $false }
            New-ExoRequest -tenantid $Userobj.tenantid -cmdlet "Set-DistributionGroup" -cmdParams $params
        }
        else {
            $Params = @{ Identity = $userobj.groupid; RequireSenderAuthenticationEnabled = $false }
            New-ExoRequest -tenantid $Userobj.tenantid -cmdlet "Set-UnifiedGroup" -cmdParams $params
        }
        $body = $results.add("Allowed external senders to send to $($userobj.Groupid).")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Allowed external senders to send to $($userobj.Groupid)" -Sev "Error"

    }
    catch {
        $body = $results.add("Failed to allow external senders to send to $($userobj.Groupid).")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Failed to allow external senders for $($userobj.Groupid). $($_.Exception.Message)" -Sev "Error"
    }

}

$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
