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
$upn = "notrequired@notrequired.com" 
$tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenantFilter).Authorization -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenantFilter)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ea Stop


$RemoveFullAccess = ($Request.body.RemoveFullAccess).Split([Environment]::NewLine)
foreach ($RemoveUser in $RemoveFullAccess | Where-Object { $_ -ne "" } ) { 
    try {
        $ImportedSession = Import-PSSession $session -ea Stop -AllowClobber -CommandName "Remove-mailboxpermission"
        $MailboxPerms = Remove-mailboxpermission -identity $userid -user $RemoveUser -AccessRights FullAccess -erroraction stop -confirm:$false
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
        $ImportedSession = Import-PSSession $session -ea Stop -AllowClobber -CommandName "Add-mailboxPermission"
        $MailboxPerms = Add-MailboxPermission -identity $userid -user $UserAutomap -automapping $true -AccessRights FullAccess -InheritanceType All -erroraction stop -confirm:$false
        $results.add( "added $($Request.body.AccessAutomap) to $($username) Mailbox with automapping")
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
        $ImportedSession = Import-PSSession $session -ea Stop -AllowClobber -CommandName "Add-mailboxPermission"
        $MailboxPerms = Add-MailboxPermission -identity $userid -user $UserNoAutomap -automapping $false -AccessRights FullAccess -InheritanceType All -erroraction stop -confirm:$false
        $results.add( "added $($Request.body.AccessAutomap) to $($username) Mailbox without automapping")
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Gave full permissions to $($request.body.AccessAutomap) on $($username)" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not add mailbox permissions for $($request.body.AccessAutomap) on $($username)" -Sev "Error" -tenant $TenantFilter
        $results.add(  "Could not add shared mailbox permissions for $($username). Error: $($_.Exception.Message)")
    }
}

Get-PSSession | Remove-PSSession
$body = [pscustomobject]@{"Results" = $($results -join '<br>') }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
