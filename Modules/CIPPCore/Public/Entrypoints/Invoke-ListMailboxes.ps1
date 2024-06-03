using namespace System.Net

Function Invoke-ListMailboxes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Mailbox'
            cmdParams = @{resultsize = 'unlimited' }
            Select    = $select
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

}
