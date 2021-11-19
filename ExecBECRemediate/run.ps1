using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."

$TenantFilter = $request.body.tenantfilter
$SuspectUser = $($request.body.userid)
Write-Host $TenantFilter
Write-Host $SuspectUser
try {
    $password = -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count 12)
    $mustChange = 'true'
    $passwordProfile = @"
{"passwordProfile": { "forceChangePasswordNextSignIn": $mustChange, "password": "$password" }}'
"@
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser" -tenantid $TenantFilter -type PATCH -body $passwordProfile  -verbose
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":"false"}'  -verbose
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser/revokeSignInSessions" -tenantid $TenantFilter -type POST -body '{}'  -verbose
    $upn = "notRequired@required.com"
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenantfilter).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-inboxRule", "Disable-InboxRule"
    Get-InboxRule -mailbox $SuspectUser | Disable-InboxRule 
    Get-PSSession | Remove-PSSession
    $results = [pscustomobject]@{"Results" = "Executed Remediation for $SuspectUser and tenant $($TenantFilter). The temporary is $password and must be changed at next logon." }

}
catch {
    #Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to assign app $($appFilter): $($_.Exception.Message)" -Sev "Error"
    $results = [pscustomobject]@{"Results" = "Failed to execute remediation. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ($Results)
    })
