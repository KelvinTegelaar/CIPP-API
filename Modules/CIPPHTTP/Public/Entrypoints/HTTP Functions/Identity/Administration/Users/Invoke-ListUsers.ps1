Function Invoke-ListUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Lists Entra ID users for a tenant with license and sign-in details, or retrieves a specific user by ID. For AllTenants or cached data, consider using ListDBCache with type=Users for significantly better performance.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $ConversionTable = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $GraphFilter = $Request.Query.graphFilter
    $userid = $Request.Query.UserID

    # When fetching a single user, use an explicit $select so directory/schema extension properties are
    # returned. Covers the properties the user view and edit form consume, any attributes added via
    # Preferences > Added Attributes, and custom data attributes mapped for manual entry on users.
    $SelectParam = ''
    if ($userid -and $TenantFilter -ne 'AllTenants') {
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

    $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
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
        $UserData | ForEach-Object {
            $SkuID = $_.AssignedLicenses.skuid
            $_ | Add-Member -NotePropertyMembers ([ordered]@{
                    onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
                    username              = ($_.userPrincipalName -split '@' | Select-Object -First 1)
                    Aliases               = ($_.ProxyAddresses -join ', ')
                    LicJoined             = ((@($SkuID | ForEach-Object { ($ConversionTable | Where-Object guid -EQ ([string]$_) | Select-Object -First 1 -ExpandProperty Product_Display_Name) }) -join ', '))
                    primDomain            = @{value = ($_.userPrincipalName -split '@' | Select-Object -Last 1); label = ($_.userPrincipalName -split '@' | Select-Object -Last 1); }
                }) -Force
            $_
        }
    } elseif ($null -ne (Get-CippRequestContext).AllowedTenants) {
        # Deprecated cacheusers blob has no reliable per-tenant column, so it cannot be safely
        # narrowed for a tenant-restricted caller - including one whose scope resolved to zero
        # tenants, whose empty array is falsy and would otherwise fall through to the legacy
        # path. Return the deprecation message instead of leaking every tenant's users.
        # Unrestricted callers ($null scope) keep the legacy behavior below.
        [PSCustomObject]@{
            Message = 'This function has been deprecated for all users, please use ListGraphRequest instead'
        }
    } else {
        $Table = Get-CIPPTable -TableName 'cacheusers'
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            [PSCustomObject]@{
                Message = 'This function has been deprecated for all users, please use ListGraphRequest instead'
            }
        } else {
            $Rows.Data | ConvertFrom-Json | Select-Object $SelectList | ForEach-Object {
                $_.onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
                $_.Aliases = $_.proxyAddresses -join ', '
                $SkuID = $_.AssignedLicenses.skuid
                $_.LicJoined = (@($SkuID | ForEach-Object { ($ConversionTable | Where-Object guid -EQ ([string]$_) | Select-Object -First 1 -ExpandProperty Product_Display_Name) }) -join ', ')
                $_.primDomain = @{value = ($_.userPrincipalName -split '@' | Select-Object -Last 1) }
                $_
            }
        }
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
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
