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

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Mailbox'
            cmdParams = @{}
            Select    = $Select
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

        foreach ($Param in $Request.Query.PSObject.Properties.Name) {
            $CmdParam = $AllowedParameters | Where-Object { $_.Parameter -eq $Param }
            if ($CmdParam) {
                switch ($CmdParam.Type) {
                    'String' {
                        if (![string]::IsNullOrEmpty($Request.Query.$Param)) {
                            $ExoRequest.cmdParams.$Param = $Request.Query.$Param
                        }
                    }
                    'Bool' {
                        $ParamIsTrue = $false
                        [bool]::TryParse($Request.Query.$Param, [ref]$ParamIsTrue) | Out-Null
                        if ($ParamIsTrue -eq $true) {
                            $ExoRequest.cmdParams.$Param = $true
                        }
                    }
                }
            }
        }

        $GraphRequest = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },

        @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
        @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
        @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
        @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
        @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
        @{Name = 'ForwardingSmtpAddress'; Expression = { $_.'ForwardingSmtpAddress' -replace 'smtp:', '' } },
        @{Name = 'InternalForwardingAddress'; Expression = { $_.'ForwardingAddress' } },
        DeliverToMailboxAndForward,
        HiddenFromAddressListsEnabled,
        ExternalDirectoryObjectId,
        MessageCopyForSendOnBehalfEnabled,
        MessageCopyForSentAsEnabled
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
