using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Accessed this API" -Sev "Debug"
$Username = $request.body.userID
$Tenantfilter = $request.body.tenantfilter
if ($username -eq $null) { exit }
$userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
$Results = [System.Collections.ArrayList]@()

$RemoveFullAccess = ($Request.body.RemoveFullAccess).value
foreach ($RemoveUser in $RemoveFullAccess) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Remove-mailboxpermission" -cmdParams @{Identity = $userid; user = $RemoveUser; accessRights = @("FullAccess"); }
        $results.add("Removed $($removeuser) from $($username) Shared Mailbox permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Removed $($RemoveUser) from $($username) Shared Mailbox permission" -Sev "Info" -tenant $TenantFilter 
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not remove mailbox permissions for $($removeuser) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not remove shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}
$AddFullAccess = ($Request.body.AddFullAccess).value

foreach ($UserAutomap in $AddFullAccess) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $UserAutomap; accessRights = @("FullAccess"); automapping = $true }
        $results.add( "added $($UserAutomap) to $($username) Mailbox with automapping")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave full permissions to $($UserAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($UserAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add( "Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}
$AddFullAccessNoAutoMap = ($Request.body.AddFullAccessNoAutoMap).value

foreach ($UserNoAutomap in $AddFullAccessNoAutoMap) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $UserNoAutomap; accessRights = @("FullAccess"); automapping = $false }
        $results.add( "added $UserNoAutomap to $($username) Mailbox without automapping")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave full permissions to $($UserNoAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($UserNoAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$AddSendAS = ($Request.body.AddSendAs).value

foreach ($UserSendAs in $AddSendAS) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Add-RecipientPermission" -cmdParams @{Identity = $userid; Trustee = $UserSendAs; accessRights = @("SendAs") }
        $results.add( "added $UserSendAs to $($username) with Send As permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave sendas permissions to $($UserSendAs) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($UserSendAs) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not add send-as permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$RemoveSendAs = ($Request.body.RemoveSendAs).value

foreach ($UserSendAs in $RemoveSendAs) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Remove-RecipientPermission" -cmdParams @{Identity = $userid; Trustee = $UserSendAs; accessRights = @("SendAs") }
        $results.add( "Removed $UserSendAs from $($username) with Send As permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Remove sendas permissions to $($UserSendAs) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not remove mailbox permissions for $($UserSendAs) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not remove send-as permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$AddSendOnBehalf = ($Request.body.AddSendOnBehalf).value

foreach ($UserSendOnBehalf in $AddSendOnBehalf) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $userid; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $UserSendOnBehalf}; }
        $results.add( "added $UserSendOnBehalf to $($username) with Send On Behalf Permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave send on behalf permissions to $($UserSendOnBehalf) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add send on behalf permissions for $($UserSendOnBehalf) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not add send on behalf permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$RemoveSendOnBehalf = ($Request.body.RemoveSendOnBehalf).value

foreach ($UserSendOnBehalf in $RemoveSendOnBehalf) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $userid; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $UserSendOnBehalf}; }
        $results.add( "Removed Send On Behalf Permissions $UserSendOnBehalf on $($username)")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Removed Send On Behalf Permissions to $($UserSendOnBehalf) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not Remove send on behalf permissions for $($UserSendOnBehalf) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not remove send on behalf permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
