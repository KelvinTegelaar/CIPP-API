using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Username = $request.body.userID
$Tenantfilter = $request.body.tenantfilter
if ($username -eq $null) { exit }
$userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
$Results = [System.Collections.ArrayList]@()

$RemoveFullAccess = ($Request.body.RemoveFullAccess).Split([Environment]::NewLine)
foreach ($RemoveUser in $RemoveFullAccess | Where-Object { $_ -ne "" } ) { 
    try {
        $MailboxPerms = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Remove-mailboxpermission" -cmdParams @{Identity = $userid; user = $RemoveUser; accessRights = @("FullAccess"); }
        $results.add("Removed $($removeuser) from $($username) Shared Mailbox permissions")
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Removed $($_) from $($username) Shared Mailbox permission" -Sev "Info" -tenant $TenantFilter       
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not remove mailbox permissions for $($removeuser) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add("Could not remove shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}
$AddFullAccess = ($Request.body.AddFullAccess).Split([Environment]::NewLine)

foreach ($UserAutomap in $AddFullAccess | Where-Object { $_ -ne "" } ) { 
    try {
        $MailboxPerms = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $UserAutomap; accessRights = @("FullAccess"); automapping = $true }
        $results.add( "added $($UserAutomap) to $($username) Mailbox with automapping")
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Gave full permissions to $($request.body.AccessAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add( "Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}
$AddFullAccessNoAutoMap = ($Request.body.AddFullAccessNoAutoMap).Split([Environment]::NewLine)

foreach ($UserNoAutomap in $AddFullAccessNoAutoMap | Where-Object { $_ -ne "" } ) { 
    try {
        $MailboxPerms = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $UserNoAutomap; accessRights = @("FullAccess"); automapping = $false }
        $results.add( "added $UserNoAutomap to $($username) Mailbox without automapping")
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Gave full permissions to $($request.body.AccessAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add(  "Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
