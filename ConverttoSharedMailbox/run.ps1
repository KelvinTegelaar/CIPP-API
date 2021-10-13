using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $upn = "notrequired@notrequired.com" 
    $customerId =  $Request.Query.TenantFilter 
    write-host "$customerId"
    $tokenvalue = convertto-securestring (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $customerid).Authorization -asplaintext -force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($customerId)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ea Stop
    Import-PSSession $session -ea Stop -allowclobber -commandname "Set-Mailbox"
    $Mailbox = Set-mailbox -identity $request.query.id -type Shared -ea Stop
    Remove-PSSession $session
    $Results = [pscustomobject]@{"Results" = "Succesfully completed task." }
    Log-Request -user $request.headers.'x-ms-client-principal' -message "Converted mailbox $($request.query.id) for customer $($customerId)" -Sev "Info"
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -message "Convert to shared mailbox failed: $_.Exception.Message" -Sev "Warn"
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
     Remove-PSSession $session
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
