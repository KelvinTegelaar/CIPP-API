using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."

$TenantFilter = $request.body.tenantfilter
$SuspectUser = $($request.body.userid)
Write-Host $TenantFilter
Write-Host $SuspectUser
try {
    $password = New-PasswordString
    $mustChange = 'true'
    $passwordProfile = @"
{"passwordProfile": { "forceChangePasswordNextSignIn": $mustChange, "password": "$password" }}'
"@
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser" -tenantid $TenantFilter -type PATCH -body $passwordProfile  -verbose
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":"false"}'  -verbose
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser/revokeSignInSessions" -tenantid $TenantFilter -type POST -body '{}'  -verbose
    $Mailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet "get-inboxrule" -cmdParams @{Mailbox = $SuspectUser } -anchor $SuspectUser | ForEach-Object {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Disable-InboxRule" -cmdParams @{Confirm = $false; Identity = $_.Identity } -anchor $SuspectUser 
    } 
    $results = [pscustomobject]@{"Results" = "Executed Remediation for $SuspectUser and tenant $($TenantFilter). The temporary password is $password and must be changed at next logon." }

}
catch {
    #Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to assign app $($appFilter): $($_.Exception.Message)" -Sev "Error"
    $results = [pscustomobject]@{"Results" = "Failed to execute remediation. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ($Results)
    })
