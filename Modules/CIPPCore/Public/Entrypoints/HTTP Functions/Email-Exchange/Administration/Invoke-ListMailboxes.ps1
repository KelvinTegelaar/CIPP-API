function Invoke-ListMailboxes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPMailboxesReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving mailboxes from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Original live EXO logic
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled,PersistedCapabilities,LitigationHoldEnabled,LitigationHoldDate,LitigationHoldDuration,ComplianceTagHoldApplied,RetentionHoldEnabled,InPlaceHolds,RetentionPolicy'
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
            @{Parameter = 'Identity'; Type = 'String' }
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

        $GraphRequest = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted,
        @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
        @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
        @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
        @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
        @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
        @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
        @{ Name = 'ForwardingSmtpAddress'; Expression = { $_.'ForwardingSmtpAddress' -replace 'smtp:', '' } },
        @{ Name = 'InternalForwardingAddress'; Expression = { $_.'ForwardingAddress' } },
        DeliverToMailboxAndForward,
        HiddenFromAddressListsEnabled,
        ExternalDirectoryObjectId,
        MessageCopyForSendOnBehalfEnabled,
        MessageCopyForSentAsEnabled,
        LitigationHoldEnabled,
        LitigationHoldDate,
        LitigationHoldDuration,
        @{ Name = 'LicensedForLitigationHold'; Expression = { ($_.PersistedCapabilities -contains 'EXCHANGE_S_ARCHIVE_ADDON' -or $_.PersistedCapabilities -contains 'EXCHANGE_S_ENTERPRISE') } },
        ComplianceTagHoldApplied,
        RetentionHoldEnabled,
        InPlaceHolds,
        RetentionPolicy
        # This select also exists in ListUserMailboxDetails and should be updated if this is changed here


        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
