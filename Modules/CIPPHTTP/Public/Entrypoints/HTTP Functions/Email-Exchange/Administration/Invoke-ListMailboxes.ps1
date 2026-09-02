function Invoke-ListMailboxes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists Exchange Online mailboxes for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants. When manualPagination is also set, one page is returned per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink; cached reads only.
    $ManualPagination = $Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)
    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB) {
            try {
                if ($ManualPagination) {
                    # Rows per page, clamped between 250 and 10000. Defaults to 5000.
                    $PageSize = 5000
                    if ($Request.Query.PageSize -as [int]) {
                        $PageSize = [Math]::Min([Math]::Max([int]$Request.Query.PageSize, 250), 10000)
                    }
                    # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                    $Page = Get-CIPPMailboxesReport -TenantFilter $TenantFilter -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -ErrorAction Stop
                    $Metadata = @{}
                    if ($Page.NextToken) { $Metadata.nextLink = $Page.NextToken }
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            Body       = [PSCustomObject]@{
                                Results  = @($Page.Items)
                                Metadata = $Metadata
                            }
                        })
                }
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
        # Picker mode: address autocompletes only need the address + name, so skip the heavy field
        # set, the per-mailbox computed properties, and the extra Get-OrganizationConfig call.
        $Minimal = $Request.Query.Minimal -eq $true
        if ($Minimal) {
            $Select = 'id,UserPrincipalName,DisplayName,PrimarySMTPAddress'
        } else {
            $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress,HiddenFromAddressListsEnabled,ExternalDirectoryObjectId,IsDirSynced,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled,PersistedCapabilities,LitigationHoldEnabled,LitigationHoldDate,LitigationHoldDuration,ComplianceTagHoldApplied,RetentionHoldEnabled,InPlaceHolds,RetentionPolicy,AutoExpandingArchiveEnabled'
        }
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

        if ($Minimal) {
            $GraphRequest = @(New-ExoRequest @ExoRequest) | Select-Object Id,
            @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
            @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
            @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } }

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @($GraphRequest)
                })
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
