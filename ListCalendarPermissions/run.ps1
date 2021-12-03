using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$UserID = $request.Query.UserID
$Tenantfilter = $request.Query.tenantfilter
Write-Information "My username is $UserID"
Write-Information "My tenantfilter is $Tenantfilter"
if ($UserID -eq $null) { exit }
#$userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
$UserDetails = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$UserID')" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
$Results = [System.Collections.ArrayList]@()
$upn = "notrequired@notrequired.com" 
$tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenantFilter).Authorization -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenantFilter)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ea Stop
$upn = 'notRequired@required.com'


try {
    Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-MailboxFolderPermission"
    # $CalPerms = (Get-MailboxFolderPermission -Identity $($userid.PrimarySmtpAddress))
    $CalPerms = (Get-MailboxFolderPermission -Identity $($UserDetails.PrimarySmtpAddress))

    Get-PSSession | Remove-PSSession
    Log-request -API 'List Calendar Permissions' -tenant $tenantfilter -message "Calendar permissions listed for $($tenantfilter)" -sev Info
} catch {
    Log-request -API 'List Calendar Permissions' -tenant $tenantfilter -message "Failed to list calendar permissions. Error: $($_.exception.message)" -sev Error
}
    
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $CalPerms
})
