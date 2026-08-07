function Invoke-ListMailboxes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists Exchange Online mailboxes for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB) {
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
        $ZeroArchiveGuid = '00000000-0000-0000-0000-000000000000'
        $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,IsDirSynced,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled,PersistedCapabilities,LitigationHoldEnabled,LitigationHoldDate,LitigationHoldDuration,ComplianceTagHoldApplied,RetentionHoldEnabled,InPlaceHolds,RetentionPolicy,AutoExpandingArchiveEnabled'
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

        $QueryParamNames = if ($Request.Query -is [System.Collections.IDictionary]) { @($Request.Query.Keys) } else { $Request.Query.PSObject.Properties.Name }
        foreach ($Param in $QueryParamNames) {
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

        $OrgAutoExpandingArchiveEnabled = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OrganizationConfig' -Select 'AutoExpandingArchiveEnabled').AutoExpandingArchiveEnabled

        $GraphRequest = foreach ($Mailbox in @(New-ExoRequest @ExoRequest)) {
            $AutoExpandingArchiveState = Get-CIPPAutoExpandingArchiveState -MailboxAutoExpandingArchiveEnabled $Mailbox.AutoExpandingArchiveEnabled -OrgAutoExpandingArchiveEnabled $OrgAutoExpandingArchiveEnabled
            # Id, not id: Select-Object matches case-insensitively but emits the object's
            # own casing, and JSON is case-sensitive.
            $Mailbox | Select-Object Id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted,
            @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
            @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
            @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
            @{ Name = 'ArchiveEnabled'; Expression = { $_.ArchiveGuid -and $_.ArchiveGuid.ToString() -ne $ZeroArchiveGuid } },
            @{ Name = 'AutoExpandingArchive'; Expression = { $AutoExpandingArchiveState.AutoExpandingArchive } },
            @{ Name = 'AutoExpandingArchiveScope'; Expression = { $AutoExpandingArchiveState.AutoExpandingArchiveScope } },
            @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
            @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
            @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
            @{ Name = 'ForwardingSmtpAddress'; Expression = { $_.'ForwardingSmtpAddress' -replace 'smtp:', '' } },
            @{ Name = 'InternalForwardingAddress'; Expression = { $_.'ForwardingAddress' } },
            DeliverToMailboxAndForward,
            HiddenFromAddressListsEnabled,
            ExternalDirectoryObjectId,
            IsDirSynced,
            MessageCopyForSendOnBehalfEnabled,
            MessageCopyForSentAsEnabled,
            LitigationHoldEnabled,
            LitigationHoldDate,
            LitigationHoldDuration,
            @{ Name = 'LicensedForLitigationHold'; Expression = { ($_.PersistedCapabilities -contains 'EXCHANGE_S_ARCHIVE_ADDON' -or $_.PersistedCapabilities -contains 'BPOS_S_ArchiveAddOn' -or $_.PersistedCapabilities -contains 'EXCHANGE_S_ENTERPRISE' -or $_.PersistedCapabilities -contains 'BPOS_S_DlpAddOn' -or $_.PersistedCapabilities -contains 'BPOS_S_Enterprise') } },
            ComplianceTagHoldApplied,
            RetentionHoldEnabled,
            InPlaceHolds,
            RetentionPolicy
        }
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
