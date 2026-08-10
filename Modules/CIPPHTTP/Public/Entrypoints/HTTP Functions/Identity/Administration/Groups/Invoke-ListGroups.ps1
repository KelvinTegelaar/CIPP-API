function Invoke-ListGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.Read
    .DESCRIPTION
        Lists Entra ID groups for a tenant, including group members and owners. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $GroupID = $Request.Query.groupID
    # Type of the group named by groupID, used to pick the owners lookup. This does NOT filter the group list.
    $GroupType = $Request.Query.groupType
    # Return the members of the group named by groupID instead of the group list. Requires groupID.
    $Members = $Request.Query.members -eq $true
    # Return the owners of the group named by groupID instead of the group list. Requires groupID.
    $Owners = $Request.Query.owners -eq $true

    # Expand each listed group's members inline. Graph allows only one expand, and members wins over owners.
    $ExpandMembers = $Request.Query.expandMembers -eq $true
    # Expand each listed group's owners inline. Ignored when expandMembers is also set.
    $ExpandOwners = $Request.Query.expandOwners -eq $true
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    # members/owners read groups/<groupID>/..., so without a groupID the URL collapses to
    # groups//members and the failure surfaces as an opaque parameter binding error.
    if (($Members -or $Owners) -and -not $GroupID) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "The 'members' and 'owners' parameters require 'groupID' to be set." }
            })
    }

    # Cache path: list view only — skip when fetching a specific group's details
    if ((-not $GroupID) -and (-not $Members) -and (-not $Owners) -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB)) {
        try {
            $GraphRequest = Get-CIPPGroupsReport -TenantFilter $TenantFilter -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
        }
        return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @($GraphRequest) })
    }

    $SelectString = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,onPremisesSyncEnabled,resourceProvisioningOptions,assignedLicenses,userPrincipalName,licenseProcessingState'
    # Graph allows only one navigational $expand on groups; members wins if both are requested
    if ($ExpandMembers) {
        $SelectString = '{0}&$expand=members($select=userPrincipalName)' -f $SelectString
    } elseif ($ExpandOwners) {
        $SelectString = '{0}&$expand=owners($select=userPrincipalName)' -f $SelectString
    }


    $BulkRequestArrayList = [System.Collections.Generic.List[object]]::new()

    if ($Request.Query.GroupID) {
        $SelectString = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,assignedLicenses,userPrincipalName,onPremisesSyncEnabled,licenseProcessingState'
        $BulkRequestArrayList.add(@{
                id     = 1
                method = 'GET'
                url    = "groups/$($GroupID)?`$select=$SelectString"
            })
    }
    if ($Members) {
        $SelectString = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
        $BulkRequestArrayList.add(@{
                id     = 2
                method = 'GET'
                url    = "groups/$($GroupID)/members?`$top=999&select=$SelectString"
            })
    }

    if ($Owners) {
        if ($GroupType -ne 'Distribution List' -and $GroupType -ne 'Mail-Enabled Security') {
            $SelectString = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
            $BulkRequestArrayList.add(@{
                    id     = 3
                    method = 'GET'
                    url    = "groups/$($GroupID)/owners?`$top=999&select=$SelectString"
                })
        } else {
            $OwnerIds = New-ExoRequest -cmdlet 'Get-DistributionGroup' -tenantid $TenantFilter -cmdParams @{Identity = $GroupID } -Select 'ManagedBy' -useSystemMailbox $true | Select-Object -ExpandProperty ManagedBy

            $BulkRequestArrayList.add(@{
                    id      = 3
                    method  = 'POST'
                    url     = 'directoryObjects/getByIds'
                    body    = @{
                        ids = @($OwnerIds)
                    }
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                })
        }
    }

    if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
        # get the outside the organization RequireSenderAuthenticationEnabled setting
        $OnlyAllowInternal = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{Identity = $GroupID } -Select 'RequireSenderAuthenticationEnabled' -useSystemMailbox $true | Select-Object -ExpandProperty RequireSenderAuthenticationEnabled
    } elseif ($GroupType -eq 'Microsoft 365') {
        $UnifiedGroupInfo = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-UnifiedGroup' -cmdParams @{Identity = $GroupID } -Select 'RequireSenderAuthenticationEnabled,subscriptionEnabled,AutoSubscribeNewMembers,HiddenFromExchangeClientsEnabled' -useSystemMailbox $true
        $OnlyAllowInternal = $UnifiedGroupInfo.RequireSenderAuthenticationEnabled
    } else {
        $OnlyAllowInternal = $null
    }

    if ($GroupType -eq 'Microsoft 365') {
        if ($UnifiedGroupInfo.subscriptionEnabled -eq $true -and $UnifiedGroupInfo.AutoSubscribeNewMembers -eq $true) { $SendCopies = $true } else { $SendCopies = $false }
    } else {
        $SendCopies = $null
    }

    try {
        if ($BulkRequestArrayList.Count -gt 0) {
            $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequestArrayList) -asapp $true
            $GraphRequest = [PSCustomObject]@{
                groupInfo              = ($RawGraphRequest | Where-Object { $_.id -eq 1 }).body | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split '@' | Select-Object -Last 1 } },
                @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -like '*Team*') { $true } else { $false } } },
                @{Name = 'groupType'; Expression = {
                        if ($_.groupTypes -contains 'Unified') { 'Microsoft 365' }
                        elseif ($_.mailEnabled -and $_.securityEnabled) { 'Mail-Enabled Security' }
                        elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'Security' }
                        elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'Distribution List' }
                    }
                },
                @{Name = 'calculatedGroupType'; Expression = {
                        if ($_.groupTypes -contains 'Unified') { 'm365' }
                        elseif ($_.mailEnabled -and $_.securityEnabled) { 'security' }
                        elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'generic' }
                        elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'distributionList' }
                    }
                },
                @{Name = 'dynamicGroupBool'; Expression = { if ($_.groupTypes -contains 'DynamicMembership') { $true } else { $false } } }
                members                = @(($RawGraphRequest | Where-Object { $_.id -eq 2 }).body.value | Sort-Object displayName)
                owners                 = @(($RawGraphRequest | Where-Object { $_.id -eq 3 }).body.value | Sort-Object displayName)
                allowExternal          = (!$OnlyAllowInternal)
                sendCopies             = $SendCopies
                hideFromOutlookClients = if ($GroupType -eq 'Microsoft 365') { $UnifiedGroupInfo.HiddenFromExchangeClientsEnabled } else { $null }
                SID                    = (Convert-AzureAdObjectIdToSid -ObjectID $((($RawGraphRequest | Where-Object { $_.id -eq 1 }).body).id))
            }
        } else {
            # Reached only for the plain list view: a groupID, members or owners request all
            # add a bulk sub-request above, so this branch always means "every group in the
            # tenant". The URL previously interpolated $GroupID and $Members, both necessarily
            # empty here, which produced 'groups//' and only worked because Graph tolerated it.
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$top=999&select=$SelectString" -tenantid $TenantFilter | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split '@' | Select-Object -Last 1 } },
            @{Name = 'membersCsv'; Expression = { $_.members.userPrincipalName -join ',' } },
            @{Name = 'ownersCsv'; Expression = { $_.owners.userPrincipalName -join ',' } },
            @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -like '*Team*') { $true }else { $false } } },
            @{Name = 'groupType'; Expression = {
                    if ($_.groupTypes -contains 'Unified') { 'Microsoft 365' }
                    elseif ($_.mailEnabled -and $_.securityEnabled) { 'Mail-Enabled Security' }
                    elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'Security' }
                    elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'Distribution List' }
                }
            },
            @{Name = 'calculatedGroupType'; Expression = {
                    if ($_.groupTypes -contains 'Unified') { 'm365' }
                    elseif ($_.mailEnabled -and $_.securityEnabled) { 'security' }
                    elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'generic' }
                    elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'distributionList' }
                }
            },
            @{Name = 'dynamicGroupBool'; Expression = { if ($_.groupTypes -contains 'DynamicMembership') { $true } else { $false } } },
            @{Name = 'SID'; Expression = { Convert-AzureAdObjectIdToSid -ObjectID $_.id } }
            $GraphRequest = @($GraphRequest | Sort-Object displayName)
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-Warning $_.InvocationInfo.PositionMessage
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequest
        })

}
