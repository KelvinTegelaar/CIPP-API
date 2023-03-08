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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Removed $($_) from $($username) Shared Mailbox permission" -Sev "Info" -tenant $TenantFilter 
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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave full permissions to $($request.body.AccessAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add( "Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}
$AddFullAccessNoAutoMap = ($Request.body.AddFullAccessNoAutoMap).value

foreach ($UserNoAutomap in $AddFullAccessNoAutoMap) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $UserNoAutomap; accessRights = @("FullAccess"); automapping = $false }
        $results.add( "added $UserNoAutomap to $($username) Mailbox without automapping")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave full permissions to $($request.body.AccessAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$AddSendAS = ($Request.body.AddSendAs).value

foreach ($UserSendAs in $AddSendAS) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Add-RecipientPermission" -cmdParams @{Identity = $userid; Trustee = $UserSendAs; accessRights = @("SendAs") }
        $results.add( "added $AddSendAS to $($username) with Send As permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Gave sendas permissions to $($request.body.AddSendAs) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not add send-as permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$RemoveSendAs = ($Request.body.RemoveSendAs).value

foreach ($UserSendAs in $RemoveSendAs) { 
    try {
        $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet "Remove-RecipientPermission" -cmdParams @{Identity = $userid; Trustee = $UserSendAs; accessRights = @("SendAs") }
        $results.add( "Removed $RemoveSendAs from $($username) with Send As permissions")
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Remove sendas permissions to $($request.body.AddSendAs) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME-message "Could not remove mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not remove send-as permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
