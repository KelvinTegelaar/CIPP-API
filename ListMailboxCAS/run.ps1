using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$GraphRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/CasMailbox" -Tenantid $tenantfilter -scope ExchangeOnline | select-object @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
@{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
@{ Name = 'ecpenabled'; Expression = { $_.'ECPEnabled' } },
@{ Name = 'owaenabled'; Expression = { $_.'OWAEnabled' } },
@{ Name = 'imapenabled'; Expression = { $_.'IMAPEnabled' } },
@{ Name = 'popenabled'; Expression = { $_.'POPEnabled' } },
@{ Name = 'mapienabled'; Expression = { $_.'MAPIEnabled' } },
@{ Name = 'ewsenabled'; Expression = { $_.'EWSEnabled' } },
@{ Name = 'activesyncenabled'; Expression = { $_.'ActiveSyncEnabled' } }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
