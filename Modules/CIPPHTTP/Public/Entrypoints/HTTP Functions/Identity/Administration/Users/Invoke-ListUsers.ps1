Function Invoke-ListUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Lists Entra ID users for a tenant with license and sign-in details, or retrieves a specific user by ID. Supports UseReportDB=true to serve cached users from the reporting database; AllTenants always uses the cache. When manualPagination is set on a cached read, one page is returned per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $GraphFilter = $Request.Query.graphFilter
    $userid = $Request.Query.UserID
    # Serve from the reporting database cache instead of live Graph. AllTenants always uses the cache.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink; cached reads only.
    $ManualPagination = $Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)
    $FromCache = -not $userid -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB)
    $NextToken = $null

    if ($userid -and (-not $TenantFilter -or $TenantFilter -eq 'AllTenants')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A specific tenant is required when requesting a single user.' }
            })
    }
    # GUID -> display name, first row wins
    $SkuNames = @{}
    foreach ($Row in [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv) {
        if (-not $SkuNames.ContainsKey($Row.GUID)) { $SkuNames[$Row.GUID] = $Row.Product_Display_Name }
    }

    # When fetching a single user, use an explicit $select so directory/schema extension properties are
    # returned. Covers the properties the user view and edit form consume, any attributes added via
    # Preferences > Added Attributes, and custom data attributes mapped for manual entry on users.
    $SelectParam = ''
    if ($userid) {
        $BaseProperties = @(
            'id', 'accountEnabled', 'ageGroup', 'assignedLicenses', 'businessPhones', 'city', 'companyName',
            'consentProvidedForMinor', 'country', 'createdDateTime', 'department', 'displayName',
            'employeeHireDate', 'employeeId', 'employeeLeaveDateTime', 'employeeType', 'faxNumber',
            'givenName', 'jobTitle', 'lastPasswordChangeDateTime', 'legalAgeGroupClassification', 'mail',
            'mailNickname', 'mobilePhone', 'officeLocation', 'onPremisesDistinguishedName', 'onPremisesDomainName',
            'onPremisesImmutableId', 'onPremisesLastSyncDateTime', 'onPremisesSamAccountName', 'onPremisesSecurityIdentifier',
            'onPremisesSyncEnabled', 'onPremisesUserPrincipalName', 'otherMails', 'postalCode',
            'preferredLanguage', 'proxyAddresses', 'showInAddressList', 'state', 'streetAddress',
            'surname', 'usageLocation', 'userPrincipalName', 'userType'
        )
        $CustomAttributes = [System.Collections.Generic.List[string]]::new()
        try {
            # Attributes added via Preferences > 'Added Attributes when creating a new user'
            $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
            $EscapedUsername = $Username -replace "'", "''"
            $UserSettingsTable = Get-CippTable -tablename 'UserSettings'
            $UserSettingsEntities = Get-CIPPAzDataTableEntity @UserSettingsTable -Filter "PartitionKey eq 'UserSettings' and (RowKey eq 'allUsers' or RowKey eq '$EscapedUsername')"
            foreach ($Entity in $UserSettingsEntities) {
                foreach ($Label in (($Entity.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue).userAttributes.label)) {
                    if ($Label) { $CustomAttributes.Add($Label) }
                }
            }
            # Custom data attributes mapped for manual entry on users for this tenant
            $MappingsTable = Get-CippTable -tablename 'CustomDataMappings'
            foreach ($Entity in (Get-CIPPAzDataTableEntity @MappingsTable)) {
                $Mapping = $Entity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($Mapping.sourceType.value -ne 'manualEntry' -or $Mapping.directoryObjectType.value -ne 'user') { continue }
                $TenantList = Expand-CIPPTenantGroups -TenantFilter $Mapping.tenantFilter
                if ($TenantList.value -notcontains $TenantFilter -and $TenantList.value -notcontains 'AllTenants') { continue }
                # Schema extension names are 'schemaId.property'; Graph $select takes the schema id
                $AttributeName = ($Mapping.customDataAttribute.value -split '\.')[0]
                if ($AttributeName) { $CustomAttributes.Add($AttributeName) }
            }
        } catch {
            Write-Warning "Failed to resolve custom attributes for user $($userid): $($_.Exception.Message)"
        }
        $ValidCustomAttributes = $CustomAttributes | Where-Object { $_ -match '^[A-Za-z][A-Za-z0-9_]*$' }
        $SelectParam = '&$select=' + ((@($BaseProperties) + @($ValidCustomAttributes) | Sort-Object -Unique) -join ',')
        Write-Information $SelectParam
    }

    if (-not $FromCache) {
        try {
            $UserData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$top=999&`$filter=$GraphFilter&`$count=true&`$expand=manager(`$select=id,userPrincipalName,displayName)$SelectParam" -tenantid $TenantFilter -ComplexFilter
        } catch {
            if ($SelectParam) {
                # A preference-added attribute name Graph does not recognize fails the whole $select;
                # fall back to the default property set rather than failing the request.
                Write-Warning "ListUsers select query failed, falling back to default properties: $($_.Exception.Message)"
                $UserData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$top=999&`$filter=$GraphFilter&`$count=true&`$expand=manager(`$select=id,userPrincipalName,displayName)" -tenantid $TenantFilter -ComplexFilter
            } else {
                throw
            }
        }
    } else {
        if ($ManualPagination) {
            # Rows per page, clamped between 250 and 10000. Defaults to 5000.
            $PageSize = 5000
            if ($Request.Query.PageSize -as [int]) {
                $PageSize = [Math]::Min([Math]::Max([int]$Request.Query.PageSize, 250), 10000)
            }
            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
            $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'Users' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink
            $Rows = $Page.Items
            $NextToken = $Page.NextToken
        } else {
            $ByTenant = Get-CIPPDbItem -TenantFilter $(if ($TenantFilter -eq 'AllTenants') { 'allTenants' } else { $TenantFilter }) -Type 'Users' -ByTenant
            $Rows = foreach ($Tenant in @($ByTenant.Keys)) { $ByTenant[$Tenant] }
        }
        if ($TenantFilter -ne 'AllTenants' -and -not $Request.Query.nextLink -and -not $Rows -and -not $NextToken) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = @{ Error = "No user data found in reporting database for $TenantFilter. Sync the report data first." }
                })
        }
        $UserData = foreach ($Row in $Rows) {
            $User = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
            $User.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
            if ($TenantFilter -eq 'AllTenants') { $User.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Row.PartitionKey)) }
            $User
        }
    }

    $GraphRequest = foreach ($User in $UserData) {
        $SkuID = $User.AssignedLicenses.skuid
        $User | Add-Member -NotePropertyMembers ([ordered]@{
                onPremisesSyncEnabled = [bool]($User.onPremisesSyncEnabled)
                username              = ($User.userPrincipalName -split '@' | Select-Object -First 1)
                Aliases               = ($User.ProxyAddresses -join ', ')
                LicJoined             = (@(foreach ($Sku in $SkuID) { if ($SkuNames.ContainsKey([string]$Sku)) { $SkuNames[[string]$Sku] } }) -join ', ')
                primDomain            = @{value = ($User.userPrincipalName -split '@' | Select-Object -Last 1); label = ($User.userPrincipalName -split '@' | Select-Object -Last 1); }
            }) -Force
        $User
    }


    if ($userid -and $Request.query.IncludeLogonDetails) {
        $startDate = (Get-Date).AddDays(-7)
        $endDate = (Get-Date)
        $sessionid = Get-Random -Maximum 1000 -Minimum 1
        $SearchParam = @{
            SessionCommand = 'ReturnLargeSet'
            Operations     = @('UserLoggedIn', 'UserLoginFailed', 'TeamsSessionStarted', 'MailboxLogin')
            sessionid      = $sessionid
            startDate      = $startDate
            endDate        = $endDate
            UserIds        = @($GraphRequest.userPrincipalName)
        }
        $AuditlogsLogon = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-unifiedAuditLog' -cmdParams $SearchParam | Sort-Object -Property CreationDate | Select-Object -Last 1).auditdata | ConvertFrom-Json
        $AppName = Get-CIPPMicrosoftFirstPartyApp -AppId "$($AuditlogsLogon.applicationId)"
        $LastSignIn = [PSCustomObject]@{
            AppDisplayName  = if ($AppName) { $AppName } else { "$($AuditlogsLogon.Workload) - $($AuditlogsLogon.ApplicationId) " }
            CreatedDateTime = $AuditlogsLogon.CreationTime
            Id              = $AuditlogsLogon.errorNumber
            Status          = $AuditlogsLogon.ResultStatus
        }
        $GraphRequest = $GraphRequest | Select-Object *,
        @{ Name = 'LastSigninApplication'; Expression = { $LastSignIn.AppDisplayName } },
        @{ Name = 'LastSigninDate'; Expression = { $($LastSignIn.CreatedDateTime | Out-String) } },
        @{ Name = 'LastSigninStatus'; Expression = { $AuditlogsLogon.operation } },
        @{ Name = 'LastSigninResult'; Expression = { $LastSignIn.status } },
        @{ Name = 'LastSigninFailureReason'; Expression = { if ($LastSignIn.Id -eq 0) { 'Successfully signed in' } else { $LastSignIn.Id } } }
    }

    # Paged cached reads return { Results, Metadata }; everything else keeps the bare array.
    if ($FromCache -and $ManualPagination) {
        $Metadata = @{}
        if ($NextToken) { $Metadata.nextLink = $NextToken }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = [PSCustomObject]@{
                    Results  = @($GraphRequest)
                    Metadata = $Metadata
                }
            })
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
