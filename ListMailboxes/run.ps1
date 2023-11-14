using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    if ([bool]$Request.Query.SkipLicense -ne $true) {
        $users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/?`$top=999&`$select=id,userPrincipalName,assignedLicenses" -Tenantid $tenantfilter
    } else {
        $users = @()
    }

    $ExoRequest = @{
        tenantid  = $TenantFilter
        cmdlet    = 'Get-Mailbox'
        cmdParams = @{}
    }

    $AllowedParameters = @(
        @{Parameter = 'Anr'; Type = 'String' }
        @{Parameter = 'Archive'; Type = 'Bool' }
        @{Parameter = 'Filter'; Type = 'String' }
        @{Parameter = 'GroupMailbox'; Type = 'Bool' }
        @{Parameter = 'PublicFolder'; Type = 'Bool' }
        @{Parameter = 'RecipientTypeDetails'; Type = 'String' }
        @{Parameter = 'SoftDeletedMailbox'; Type = 'Bool' }
    )

    foreach ($Param in $Request.Query.Keys) {
        $CmdParam = $AllowedParameters | Where-Object { $_.Parameter -eq $Param }
        if ($CmdParam) {
            switch ($CmdParam.Type) {
                'String' {
                    if (![string]::IsNullOrEmpty($Request.Query.$Param)) {
                        $ExoRequest.cmdParams.$Param = $Request.Query.$Param
                    }
                }
                'Bool' {
                    if ([bool]$Request.Query.$Param -eq $true) {
                        $ExoRequest.cmdParams.$Param = $true
                    }
                }
            }
        }
    }

    Write-Host ($ExoRequest | ConvertTo-Json)

    $GraphRequest = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },

    @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
    @{ Name = 'SharedMailboxWithLicense'; Expression = {
            $ID = $_.id
            $Shared = if ($_.'RecipientTypeDetails' -eq 'SharedMailbox') { $true } else { $false }
            if (($users | Where-Object -Property ID -EQ $ID).assignedLicenses.skuid -and $Shared) { $true } else { $false }
        }
    },

    @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
    @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
    @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
    @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } }
    $StatusCode = [HttpStatusCode]::OK
} catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
