using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    $users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/?`$top=999&`$select=id,userPrincipalName,assignedLicenses" -Tenantid $tenantfilter
    $GraphRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox" -Tenantid $tenantfilter -scope ExchangeOnline | Select-Object @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
    @{ Name = 'id'; Expression = { $_.'ObjectKey' } 
    },
    @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
    @{ Name = 'SharedMailboxWithLicense'; Expression = { 
            $ID = $_.ObjectKey
            $Shared = if ($_.'RecipientTypeDetails' -eq 'SharedMailbox') { $true } else { $false }
            if (($users | Where-Object -Property ID -EQ $ID).assignedLicenses.skuid -and $Shared) { $true } else { $false } 
        } 
    },

    @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
    @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
    @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
    @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ", " } }
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
