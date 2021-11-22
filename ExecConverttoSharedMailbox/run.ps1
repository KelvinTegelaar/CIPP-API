using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $MailboxType = if ($request.query.ConvertToUser -eq 'true') { "Regular" } else { "Shared" }
    $upn = "notrequired@notrequired.com" 
    $customerId = $Request.Query.TenantFilter 
    Write-Host "$customerId"
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $customerid).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($customerId)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ea Stop
    Import-PSSession $session -ea Stop -AllowClobber -CommandName "Set-Mailbox"
    $Mailbox = Set-mailbox -identity $request.query.id -type $($MailboxType) -ea Stop
    Remove-PSSession $session
    $Results = [pscustomobject]@{"Results" = "Succesfully completed task." }
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($customerId) -message "Converted mailbox $($request.query.id)" -Sev "Info"
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($customerId) -message "Convert to shared mailbox failed: $($_.Exception.Message)" -Sev "Error"
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
    Remove-PSSession $session
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
