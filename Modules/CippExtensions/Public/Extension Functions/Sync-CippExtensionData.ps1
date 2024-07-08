function Sync-CippExtensionData {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $SyncType
    )

    $Table = Get-CIPPTable -TableName ExtensionSync
    $Extensions = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($SyncType)'"
    $LastSync = $Extensions | Where-Object { $_.RowKey -eq $TenantFilter }
    $CacheTable = Get-CIPPTable -tablename 'CacheExtensionSync'

    if (!$LastSync) {
        $LastSync = @{
            PartitionKey = $SyncType
            RowKey       = $TenantFilter
            Status       = 'Not Synced'
            Error        = ''
            LastSync     = 'Never'
        }
        Add-CIPPAzDataTableEntity @Table -Entity $LastSync
    }

    try {
        switch ($SyncType) {
            'Overview' {
                # Build bulk requests array.
                [System.Collections.Generic.List[PSCustomObject]]$TenantRequests = @(
                    @{
                        id     = 'TenantDetails'
                        method = 'GET'
                        url    = '/organization'
                    },
                    @{
                        id     = 'AllRoles'
                        method = 'GET'
                        url    = '/directoryRoles'
                    },
                    @{
                        id     = 'Domains'
                        method = 'GET'
                        url    = '/domains$top=999'
                    },
                    @{
                        id     = 'Licenses'
                        method = 'GET'
                        url    = '/subscribedSkus'
                    },
                    @{
                        id     = 'ConditionalAccess'
                        method = 'GET'
                        url    = '/identity/conditionalAccess/policies'
                    },
                    @{
                        id     = 'SecureScoreControlProfiles'
                        method = 'GET'
                        url    = '/security/secureScoreControlProfiles?$top=999'
                    },
                    @{
                        id     = 'Subscriptions'
                        method = 'GET'
                        url    = '/directory/subscriptions?$top=999'
                    },
                    @{
                        id     = 'OneDriveUsage'
                        method = 'GET'
                        url    = "reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application/json"
                    },
                    @{
                        id     = 'MailboxUsage'
                        method = 'GET'
                        url    = "reports/getMailboxUsageDetail(period='D7')?`$format=application/json"
                    }
                )

                $SingleGraphQueries = @(@{
                        id           = 'SecureScore'
                        graphRequest = @{
                            uri          = 'https://graph.microsoft.com/beta/security/secureScores?$top=1'
                            noPagination = $true
                        }
                    })
                $AdditionalRequests = @(
                    @{
                        ParentId     = 'AllRoles'
                        graphRequest = @{
                            url    = '/directoryRoles/{0}/members?$select=id,displayName,userPrincipalName'
                            method = 'GET'
                        }
                    }
                )
            }
            'Users' {
                [System.Collections.Generic.List[PSCustomObject]]$TenantRequests = @(
                    @{
                        id     = 'Users'
                        method = 'GET'
                        url    = '/users?$top=999&$select=id,accountEnabled,businessPhones,city,createdDateTime,companyName,country,department,displayName,faxNumber,givenName,isResourceAccount,jobTitle,mail,mailNickname,mobilePhone,onPremisesDistinguishedName,officeLocation,onPremisesLastSyncDateTime,otherMails,postalCode,preferredDataLocation,preferredLanguage,proxyAddresses,showInAddressList,state,streetAddress,surname,usageLocation,userPrincipalName,userType,assignedLicenses,onPremisesSyncEnabled'
                    }
                )
            }
            'Groups' {
                [System.Collections.Generic.List[PSCustomObject]]$TenantRequests = @(
                    @{
                        id     = 'Groups'
                        method = 'GET'
                        url    = '/groups?$top=999&$select=id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,grouptypes,onPremisesSyncEnabled,resourceProvisioningOptions,userPrincipalName'
                    }
                )
                $AdditionalRequests = @(
                    @{
                        ParentId     = 'Groups'
                        graphRequest = @{
                            url    = '/groups/{0}/members?$select=id,displayName,userPrincipalName'
                            method = 'GET'
                        }
                    }
                )
            }
            'Devices' {
                [System.Collections.Generic.List[PSCustomObject]]$TenantRequests = @(
                    @{
                        id     = 'Devices'
                        method = 'GET'
                        url    = '/deviceManagement/managedDevices?$top=999'
                    },
                    @{
                        id     = 'DeviceCompliancePolicies'
                        method = 'GET'
                        url    = '/deviceManagement/deviceCompliancePolicies'
                    },
                    @{
                        id     = 'DeviceApps'
                        method = 'GET'
                        url    = '/deviceAppManagement/mobileApps'
                    }
                )

                $AdditionalRequests = @(
                    @{
                        ParentId     = 'DeviceCompliancePolicies'
                        graphRequest = @{
                            url    = '/deviceManagement/deviceCompliancePolicies/{0}/deviceStatuses?$top=999'
                            method = 'GET'
                        }
                    }
                )
            }
            'Mailboxes' {
                $Select = 'id,ExchangeGuid,ArchiveGuid,UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses,WhenSoftDeleted,IsInactiveMailbox'
                $ExoRequest = @{
                    tenantid  = $TenantFilter
                    cmdlet    = 'Get-Mailbox'
                    cmdParams = @{}
                    Select    = $Select
                }
                $Mailboxes = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },

                @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
                @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
                @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
                @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
                @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } }

                $Entity = @{
                    PartitionKey = $TenantFilter
                    SyncType     = 'Mailboxes'
                    RowKey       = 'Mailboxes'
                    Data         = [string]($Mailboxes | ConvertTo-Json -Depth 10 -Compress)
                }
                Add-CIPPAzDataTableEntity @CacheTable -Entity $Entity -Force
            }
        }

        if ($TenantRequests) {
            try {
                $TenantResults = New-GraphBulkRequest -Requests $TenantRequests -tenantid $TenantFilter
            } catch {
                Throw "Failed to fetch bulk company data: $_"
            }

            if ($SingleGraphQueries) {
                foreach ($SingleGraphQuery in $SingleGraphQueries) {
                    $Request = $SingleGraphQuery.graphRequest
                    $Data = New-GraphGetRequest @Request -tenantid $TenantFilter
                    $Entity = @{
                        PartitionKey = $TenantFilter
                        SyncType     = $SyncType
                        RowKey       = $SingleGraphQuery.id
                        Data         = [string]($Data | ConvertTo-Json -Depth 10 -Compress)
                    }
                    Add-CIPPAzDataTableEntity @CacheTable -Entity $Entity -Force
                }
            }

            if ($AdditionalRequests) {
                foreach ($AdditionalRequest in $AdditionalRequests) {
                    $ParentId = $AdditionalRequest.ParentId
                    $GraphRequest = $AdditionalRequest.graphRequest.PSObject.Copy()
                    $AdditionalRequestQueries = ($TenantResults | Where-Object { $_.id -eq $ParentId }).body.value | ForEach-Object {
                        if ($_.id) {
                            [PSCustomObject]@{
                                id     = $_.id
                                method = $GraphRequest.method
                                url    = $GraphRequest.url -f $_.id
                            }
                        }
                    }
                    #Write-Information ($AdditionalRequestQueries | ConvertTo-Json -Depth 10 -Compress)
                    if (($AdditionalRequestQueries | Measure-Object).Count -gt 0) {
                        $AdditionalResults = New-GraphBulkRequest -Requests $AdditionalRequestQueries -tenantid $TenantFilter
                        $AdditionalResults | ForEach-Object {
                            $Entity = @{
                                PartitionKey = $TenantFilter
                                SyncType     = $SyncType
                                RowKey       = '{0}_{1}' -f $ParentId, $_.id
                                Data         = [string]($_.body.value | ConvertTo-Json -Depth 10 -Compress)
                            }
                            Add-CIPPAzDataTableEntity @CacheTable -Entity $Entity -Force
                        }
                    }
                }
            }

            $TenantResults | Select-Object id, body | ForEach-Object {
                $Entity = @{
                    PartitionKey = $TenantFilter
                    RowKey       = $_.id
                    SyncType     = $SyncType
                    Data         = [string]($_.body.value | ConvertTo-Json -Depth 10 -Compress)
                }
                Add-CIPPAzDataTableEntity @CacheTable -Entity $Entity -Force
            }
        }
        $LastSync.LastSync = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $LastSync.Status = 'Completed'
        $LastSync.Error = ''
    } catch {
        $LastSync.Status = 'Failed'
        $LastSync.Error = [string](Get-CippException -Exception $_ | ConvertTo-Json -Compress)
        throw "Failed to sync data: $($_.Exception.Message)"
    } finally {
        Add-CIPPAzDataTableEntity @Table -Entity $LastSync -Force
    }
}
