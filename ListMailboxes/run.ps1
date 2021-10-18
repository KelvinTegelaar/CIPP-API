using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$GraphRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox" -Tenantid $tenantfilter -scope ExchangeOnline | select-object @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
@{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
@{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
@{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
@{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
@{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | ? {$_ -clike 'smtp:*'}).Replace('smtp:','') -join ", " } }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
