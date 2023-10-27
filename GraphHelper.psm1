function Get-CIPPTable {
    [CmdletBinding()]
    param (
        $tablename = 'CippLogs'
    )
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName $tablename
    New-AzDataTable -Context $Context | Out-Null

    @{
        Context = $Context
    }
}
function Get-NormalizedError {
    [CmdletBinding()]
    param (
        [string]$message
    )
    switch -Wildcard ($message) {
        'Request not applicable to target tenant.' { 'Required license not available for this tenant' }
        "Neither tenant is B2C or tenant doesn't have premium license" { 'This feature requires a P1 license or higher' }
        'Response status code does not indicate success: 400 (Bad Request).' { 'Error 400 occured. There is an issue with the token configuration for this tenant. Please perform an access check' }
        '*Microsoft.Skype.Sync.Pstn.Tnm.Common.Http.HttpResponseException*' { 'Could not connect to Teams Admin center - Tenant might be missing a Teams license' }
        '*Provide valid credential.*' { 'Error 400: There is an issue with your Exchange Token configuration. Please perform an access check for this tenant' }
        '*This indicate that a subscription within the tenant has lapsed*' { 'There is no exchange subscription available, or it has lapsed. Check licensing information.' }
        '*User was not found.*' { 'The relationship between this tenant and the partner has been dissolved from the tenant side.' }
        '*The user or administrator has not consented to use the application*' { 'CIPP cannot access this tenant. Perform a CPV Refresh and Access Check via the settings menu' }
        '*AADSTS50020*' { 'AADSTS50020: The user you have used for your Secure Application Model is a guest in this tenant, or your are using GDAP and have not added the user to the correct group. Please delete the guest user to gain access to this tenant' }
        '*AADSTS50177' { 'AADSTS50177: The user you have used for your Secure Application Model is a guest in this tenant, or your are using GDAP and have not added the user to the correct group. Please delete the guest user to gain access to this tenant' }
        '*invalid or malformed*' { 'The request is malformed. Have you finished the SAM Setup?' }
        '*Windows Store repository apps feature is not supported for this tenant*' { 'This tenant does not have WinGet support available' }
        '*AADSTS650051*' { 'The application does not exist yet. Try again in 30 seconds.' }
        '*AppLifecycle_2210*' { 'Failed to call Intune APIs: Does the tenant have a license available?' }
        '*One or more added object references already exist for the following modified properties:*' { 'This user is already a member of this group.' }
        '*Microsoft.Exchange.Management.Tasks.MemberAlreadyExistsException*' { 'This user is already a member of this group.' }
        '*The property value exceeds the maximum allowed size (64KB)*' { 'One of the values exceeds the maximum allowed size (64KB).' }
        Default { $message }

    }
}

function Get-GraphToken($tenantid, $scope, $AsApp, $AppID, $refreshToken, $ReturnRefresh, $SkipCache) {
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }
    if (!$env:SetFromProfile) { $CIPPAuth = Get-CIPPAuthentication; Write-Host 'Could not get Refreshtoken from environment variable. Reloading token.' }
    $AuthBody = @{
        client_id     = $env:ApplicationID
        client_secret = $env:ApplicationSecret
        scope         = $Scope
        refresh_token = $env:RefreshToken
        grant_type    = 'refresh_token'
    }
    if ($asApp -eq $true) {
        $AuthBody = @{
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            scope         = $Scope
            grant_type    = 'client_credentials'
        }
    }

    if ($null -ne $AppID -and $null -ne $refreshToken) {
        $AuthBody = @{
            client_id     = $appid
            refresh_token = $RefreshToken
            scope         = $Scope
            grant_type    = 'refresh_token'
        }
    }

    if (!$tenantid) { $tenantid = $env:TenantID }

    $TokenKey = '{0}-{1}-{2}' -f $tenantid, $scope, $asApp

    try {
        if ($script:AccessTokens.$TokenKey -and [int](Get-Date -UFormat %s -Millisecond 0) -lt $script:AccessTokens.$TokenKey.expires_on -and $SkipCache -ne $true) {
            Write-Host 'Graph: cached token'
            $AccessToken = $script:AccessTokens.$TokenKey
        }
        else {
            Write-Host 'Graph: new token'
            $AccessToken = (Invoke-RestMethod -Method post -Uri "https://login.microsoftonline.com/$($tenantid)/oauth2/v2.0/token" -Body $Authbody -ErrorAction Stop)
            $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $AccessToken.expires_in
            Add-Member -InputObject $AccessToken -NotePropertyName 'expires_on' -NotePropertyValue $ExpiresOn
            if (!$script:AccessTokens) { $script:AccessTokens = [HashTable]::Synchronized(@{}) }
            $script:AccessTokens.$TokenKey = $AccessToken
        }

        if ($ReturnRefresh) { $header = $AccessToken } else { $header = @{ Authorization = "Bearer $($AccessToken.access_token)" } }
        return $header
        #Write-Host $header['Authorization']
    }
    catch {
        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant.RowKey) {
            $donotset = $true
            $Tenant = [pscustomobject]@{
                GraphErrorCount     = $null
                LastGraphTokenError = $null
                LastGraphError      = $null
                PartitionKey        = 'TenantFailed'
                RowKey              = 'Failed'
            }
        }
        $Tenant.LastGraphError = if ( $_.ErrorDetails.Message) {
            $msg = $_.ErrorDetails.Message | ConvertFrom-Json
            "$($msg.error):$($msg.error_description)"
        }
        else {
            $_.Exception.message
        }
        $Tenant.GraphErrorCount++

        if (!$donotset) { Update-AzDataTableEntity @TenantsTable -Entity $Tenant }
        throw "Could not get token: $($Tenant.LastGraphError)"
    }
}

function Write-LogMessage ($message, $tenant = 'None', $API = 'None', $tenantId = $null, $user, $sev) {
    try {
        $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    }
    catch {
        $username = $user
    }

    $Table = Get-CIPPTable -tablename CippLogs

    if (!$tenant) { $tenant = 'None' }
    if (!$username) { $username = 'CIPP' }
    if ($sev -eq 'Debug' -and $env:DebugMode -ne 'true') {
        Write-Information 'Not writing to log file - Debug mode is not enabled.'
        return
    }
    $PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString()
    $TableRow = @{
        'Tenant'       = [string]$tenant
        'API'          = [string]$API
        'Message'      = [string]$message
        'Username'     = [string]$username
        'Severity'     = [string]$sev
        'SentAsAlert'  = $false
        'PartitionKey' = $PartitionKey
        'RowKey'       = ([guid]::NewGuid()).ToString()
    }


    if ($tenantId) {
        $TableRow.Add('TenantID', [string]$tenantId)
    }
    
    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}

function New-GraphGetRequest {
    Param(
        $uri,
        $tenantid,
        $scope,
        $AsApp,
        $noPagination,
        $NoAuthCheck,
        $skipTokenCache,
        [switch]$ComplexFilter,
        [switch]$CountOnly
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        if ($scope -eq 'ExchangeOnline') {
            $AccessToken = Get-ClassicAPIToken -resource 'https://outlook.office365.com' -Tenantid $tenantid
            $headers = @{ Authorization = "Bearer $($AccessToken.access_token)" }
        }
        else {
            $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        }

        if ($ComplexFilter) {
            $headers['ConsistencyLevel'] = 'eventual'
        }
        $nextURL = $uri

        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant) {
            $Tenant = @{
                GraphErrorCount = 0
                LastGraphError  = $null
                PartitionKey    = 'TenantFailed'
                RowKey          = 'Failed'
            }
        }

        $ReturnedData = do {
            try {
                $Data = (Invoke-RestMethod -Uri $nextURL -Method GET -Headers $headers -ContentType 'application/json; charset=utf-8')
                if ($CountOnly) {
                    $Data.'@odata.count'
                    $nextURL = $null
                }
                else {
                    if ($data.value) { $data.value } else { ($Data) }
                    if ($noPagination) { $nextURL = $null } else { $nextURL = $data.'@odata.nextLink' }
                }
            }
            catch {
                $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
                if ($Message -eq $null) { $Message = $($_.Exception.Message) }
                if ($Message -ne 'Request not applicable to target tenant.' -and $Tenant) {
                    $Tenant.LastGraphError = $Message
                    $Tenant.GraphErrorCount++
                    Update-AzDataTableEntity @TenantsTable -Entity $Tenant
                }
                throw $Message
            }
        } until ($null -eq $NextURL)
        $Tenant.LastGraphError = ''
        Update-AzDataTableEntity @TenantsTable -Entity $Tenant
        return $ReturnedData
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function New-GraphPOSTRequest ($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders) {
    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        if ($AddedHeaders) {
            foreach ($header in $AddedHeaders.getenumerator()) {
                $headers.Add($header.Key, $header.Value)
            }
        }
        Write-Verbose "Using $($uri) as url"
        if (!$type) {
            $type = 'POST'
        }

        try {
            $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType 'application/json; charset=utf-8')
        }
        catch {
            $ErrorMess = $($_.Exception.Message)
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
            if (!$Message) { $Message = $ErrorMess }
            throw $Message
        }
        return $ReturnedData
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function convert-skuname($skuname, $skuID) {
    Set-Location (Get-Item $PSScriptRoot).FullName
    $ConvertTable = Import-Csv Conversiontable.csv
    if ($skuname) { $ReturnedName = ($ConvertTable | Where-Object { $_.String_Id -eq $skuname } | Select-Object -Last 1).'Product_Display_Name' }
    if ($skuID) { $ReturnedName = ($ConvertTable | Where-Object { $_.guid -eq $skuid } | Select-Object -Last 1).'Product_Display_Name' }
    if ($ReturnedName) { return $ReturnedName } else { return $skuname, $skuID }
}

function Get-ClassicAPIToken($tenantID, $Resource) {
    $TokenKey = '{0}-{1}' -f $TenantID, $Resource
    if ($script:classictoken.$TokenKey -and [int](Get-Date -UFormat %s -Millisecond 0) -lt $script:classictoken.$TokenKey.expires_on) {
        Write-Host 'Classic: cached token'
        return $script:classictoken.$TokenKey
    }
    else {
        Write-Host 'Using classic'
        $uri = "https://login.microsoftonline.com/$($TenantID)/oauth2/token"
        $Body = @{
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            resource      = $Resource
            refresh_token = $env:RefreshToken
            grant_type    = 'refresh_token'
        }
        try {
            if (!$script:classictoken) { $script:classictoken = [HashTable]::Synchronized(@{}) }
            $script:classictoken.$TokenKey = Invoke-RestMethod $uri -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction SilentlyContinue -Method post
            return $script:classictoken.$TokenKey
        }
        catch {
            # Track consecutive Graph API failures
            $TenantsTable = Get-CippTable -tablename Tenants
            $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
            $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
            if (!$Tenant) {
                $Tenant = @{
                    GraphErrorCount     = $null
                    LastGraphTokenError = $null
                    LastGraphError      = $null
                    PartitionKey        = 'TenantFailed'
                    RowKey              = 'Failed'
                }
            }
            $Tenant.LastGraphError = $_.Exception.Message
            $Tenant.GraphErrorCount++

            Update-AzDataTableEntity @TenantsTable -Entity $Tenant
            Throw "Failed to obtain Classic API Token for $TenantID - $_"
        }
    }
}

function New-TeamsAPIGetRequest($Uri, $tenantID, $Method = 'GET', $Resource = '48ac35b8-9aa8-4d74-927d-1f4a14a0b239', $ContentType = 'application/json') {

    if ((Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $token = Get-ClassicAPIToken -Tenant $tenantid -Resource $Resource

        $NextURL = $Uri
        $ReturnedData = do {
            try {
                $Data = Invoke-RestMethod -ContentType "$ContentType;charset=UTF-8" -Uri $NextURL -Method $Method -Headers @{
                    Authorization            = "Bearer $($token.access_token)";
                    'x-ms-client-request-id' = [guid]::NewGuid().ToString();
                    'x-ms-client-session-id' = [guid]::NewGuid().ToString()
                    'x-ms-correlation-id'    = [guid]::NewGuid()
                    'X-Requested-With'       = 'XMLHttpRequest'
                    'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9'

                }
                $Data
                if ($noPagination) { $nextURL = $null } else { $nextURL = $data.NextLink }
            }
            catch {
                throw "Failed to make Teams API Get Request $_"
            }
        } until ($null -eq $NextURL)
        return $ReturnedData
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function New-ClassicAPIGetRequest($TenantID, $Uri, $Method = 'GET', $Resource = 'https://admin.microsoft.com', $ContentType = 'application/json') {

    if ((Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $token = Get-ClassicAPIToken -Tenant $tenantID -Resource $Resource

        $NextURL = $Uri
        $ReturnedData = do {
            try {
                $Data = Invoke-RestMethod -ContentType "$ContentType;charset=UTF-8" -Uri $NextURL -Method $Method -Headers @{
                    Authorization            = "Bearer $($token.access_token)";
                    'x-ms-client-request-id' = [guid]::NewGuid().ToString();
                    'x-ms-client-session-id' = [guid]::NewGuid().ToString()
                    'x-ms-correlation-id'    = [guid]::NewGuid()
                    'X-Requested-With'       = 'XMLHttpRequest'
                }
                $Data
                if ($noPagination) { $nextURL = $null } else { $nextURL = $data.NextLink }
            }
            catch {
                throw "Failed to make Classic Get Request $_"
            }
        } until ($null -eq $NextURL)
        return $ReturnedData
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function New-ClassicAPIPostRequest($TenantID, $Uri, $Method = 'POST', $Resource = 'https://admin.microsoft.com', $Body) {

    if ((Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $token = Get-ClassicAPIToken -Tenant $tenantID -Resource $Resource
        try {
            $ReturnedData = Invoke-RestMethod -ContentType 'application/json;charset=UTF-8' -Uri $Uri -Method $Method -Body $Body -Headers @{
                Authorization                  = "Bearer $($token.access_token)";
                'x-ms-client-request-id'       = [guid]::NewGuid().ToString();
                'x-ms-client-session-id'       = [guid]::NewGuid().ToString()
                'x-ms-correlation-id'          = [guid]::NewGuid()
                'X-Requested-With'             = 'XMLHttpRequest'
                'X-RequestForceAuthentication' = $true

            }

        }
        catch {
            throw "Failed to make Classic Get Request $_"
        }
        return $ReturnedData
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function Get-AuthorisedRequest {
    [CmdletBinding()]
    Param(
        [string]$TenantID,
        [string]$Uri
    )
    if (!$TenantID) {
        $TenantID = $env:TenantId
    }
    if ($Uri -like 'https://graph.microsoft.com/beta/contracts*' -or $Uri -like '*/customers/*' -or $Uri -eq 'https://graph.microsoft.com/v1.0/me/sendMail' -or $Uri -like '*/tenantRelationships/*') {
        return $true
    }
    $Tenants = Get-Tenants -IncludeErrors
    $SkipList = Get-Tenants -SkipList
    if (($env:PartnerTenantAvailable -eq $true -and $SkipList.customerId -notcontains $TenantID -and $SkipList.defaultDomainName -notcontains $TenantID) -or (($Tenants.customerId -contains $TenantID -or $Tenants.defaultDomainName -contains $TenantID) -and $TenantID -ne $env:TenantId)) {
        return $true
    }
    else {
        return $false
    }
}


function Get-Tenants {
    param (
        [Parameter( ParameterSetName = 'Skip', Mandatory = $True )]
        [switch]$SkipList,
        [Parameter( ParameterSetName = 'Standard')]
        [switch]$IncludeAll,
        [switch]$IncludeErrors
    )

    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $ExcludedFilter = "PartitionKey eq 'Tenants' and Excluded eq true"

    $SkipListCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter
    if ($SkipList) {
        return $SkipListCache
    }

    if ($IncludeAll.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants'"
    }
    elseif ($IncludeErrors.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    }
    else {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false and GraphErrorCount lt 50"
    }
    $IncludedTenantsCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter

    if (($IncludedTenantsCache | Measure-Object).Count -gt 0) {
        try {
            $LastRefresh = ($IncludedTenantsCache | Where-Object { $_.customerId } | Sort-Object LastRefresh -Descending | Select-Object -First 1).LastRefresh | Get-Date -ErrorAction Stop
        }
        catch { $LastRefresh = $false }
    }
    else {
        $LastRefresh = $false
    }
    if (!$LastRefresh -or $LastRefresh -lt (Get-Date).Addhours(-24).ToUniversalTime()) {
        try {
            Write-Host "Renewing. Cache not hit. $LastRefresh"
            $TenantList = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/tenants?`$top=999" -tenantid $env:TenantID ) | Select-Object id, @{l = 'customerId'; e = { $_.tenantId } }, @{l = 'DefaultdomainName'; e = { [string]($_.contract.defaultDomainName) } } , @{l = 'MigratedToNewTenantAPI'; e = { $true } }, DisplayName, domains, @{n = 'delegatedPrivilegeStatus'; exp = { $_.tenantStatusInformation.delegatedPrivilegeStatus } } | Where-Object { $_.defaultDomainName -NotIn $SkipListCache.defaultDomainName -and $_.defaultDomainName -ne $null }

        }
        catch {
            Write-Host "Get-Tenants - Lighthouse Error, using contract/delegatedAdminRelationship calls. Error: $($_.Exception.Message)"
            [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @(
                @{
                    id     = 'Contracts'
                    method = 'GET'
                    url    = "/contracts?`$top=999"
                },
                @{
                    id     = 'GDAPRelationships'
                    method = 'GET'
                    url    = '/tenantRelationships/delegatedAdminRelationships'
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter -NoAuthCheck:$true
            $Contracts = Get-GraphBulkResultByID -Results $BulkResults -ID 'Contracts' -Value
            $GDAPRelationships = Get-GraphBulkResultByID -Results $BulkResults -ID 'GDAPRelationships' -Value

            $ContractList = $Contracts | Select-Object id, customerId, DefaultdomainName, DisplayName, domains, @{l = 'MigratedToNewTenantAPI'; e = { $true } }, @{ n = 'delegatedPrivilegeStatus'; exp = { $CustomerId = $_.customerId; if (($GDAPRelationships | Where-Object { $_.customer.tenantId -EQ $CustomerId -and $_.status -EQ 'active' } | Measure-Object).Count -gt 0) { 'delegatedAndGranularDelegetedAdminPrivileges' } else { 'delegatedAdminPrivileges' } } } | Where-Object -Property defaultDomainName -NotIn $SkipListCache.defaultDomainName

            $GDAPOnlyList = $GDAPRelationships | Where-Object { $_.status -eq 'active' -and $Contracts.customerId -notcontains $_.customer.tenantId } | Select-Object id, @{l = 'customerId'; e = { $($_.customer.tenantId) } }, @{l = 'defaultDomainName'; e = { (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$($_.customer.tenantId)')" -noauthcheck $true -asApp:$true -tenant $env:TenantId).defaultDomainName } }, @{l = 'MigratedToNewTenantAPI'; e = { $true } }, @{n = 'displayName'; exp = { $_.customer.displayName } }, domains, @{n = 'delegatedPrivilegeStatus'; exp = { 'granularDelegatedAdminPrivileges' } } |  Where-Object { $_.defaultDomainName -NotIn $SkipListCache.defaultDomainName -and $_.defaultDomainName -ne $null }  | Sort-Object -Property customerId -Unique

            $TenantList = @($ContractList) + @($GDAPOnlyList)
        }
        <#if (!$TenantList.customerId) {
            $TenantList = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contracts?`$top=999" -tenantid $env:TenantID ) | Select-Object id, customerId, DefaultdomainName, DisplayName, domains | Where-Object -Property defaultDomainName -NotIn $SkipListCache.defaultDomainName
        }#>
        $IncludedTenantsCache = [system.collections.generic.list[hashtable]]::new()
        if ($env:PartnerTenantAvailable) {
            $IncludedTenantsCache.Add(@{
                    RowKey            = $env:TenantID
                    PartitionKey      = 'Tenants'
                    customerId        = $env:TenantID
                    defaultDomainName = $env:TenantID
                    displayName       = '*Partner Tenant'
                    domains           = 'PartnerTenant'
                    Excluded          = $false
                    ExcludeUser       = ''
                    ExcludeDate       = ''
                    GraphErrorCount   = 0
                    LastGraphError    = ''
                    LastRefresh       = (Get-Date).ToUniversalTime()
                }) | Out-Null
        }
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName -eq 'Invalid') { continue }
            $IncludedTenantsCache.Add(@{
                    RowKey                   = [string]$Tenant.customerId
                    PartitionKey             = 'Tenants'
                    customerId               = [string]$Tenant.customerId
                    defaultDomainName        = [string]$Tenant.defaultDomainName
                    displayName              = [string]$Tenant.DisplayName
                    delegatedPrivilegeStatus = [string]$Tenant.delegatedPrivilegeStatus
                    domains                  = ''
                    Excluded                 = $false
                    ExcludeUser              = ''
                    ExcludeDate              = ''
                    GraphErrorCount          = 0
                    LastGraphError           = ''
                    LastRefresh              = (Get-Date).ToUniversalTime()
                }) | Out-Null
        }

        if ($IncludedTenantsCache) {
            $TenantsTable.Force = $true
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache
        }
    }
    return ($IncludedTenantsCache | Sort-Object -Property displayName)

}

function Remove-CIPPCache {
    param (
        $TenantsOnly
    )
    # Remove all tenants except excluded
    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    $ClearIncludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
    Remove-AzDataTableEntity @TenantsTable -Entity $ClearIncludedTenants
    if ($tenantsonly -eq 'false') {
        Write-Host 'Clearing all'
        # Remove Domain Analyser cached results
        $DomainsTable = Get-CippTable -tablename 'Domains'
        $Filter = "PartitionKey eq 'TenantDomains'"
        $ClearDomainAnalyserRows = Get-CIPPAzDataTableEntity @DomainsTable -Filter $Filter | ForEach-Object {
            $_.DomainAnalyser = ''
            $_
        }
        Update-AzDataTableEntity @DomainsTable -Entity $ClearDomainAnalyserRows
        #Clear BPA
        $BPATable = Get-CippTable -tablename 'cachebpa'
        $ClearBPARows = Get-CIPPAzDataTableEntity @BPATable
        Remove-AzDataTableEntity @BPATable -Entity $ClearBPARows
        $ENV:SetFromProfile = $null
        $Script:SkipListCache = $Null
        $Script:SkipListCacheEmpty = $Null
        $Script:IncludedTenantsCache = $Null
    }
}

function New-ExoRequest ($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, $Anchor, $NoAuthCheck) {
    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        $token = Get-ClassicAPIToken -resource 'https://outlook.office365.com' -Tenantid $tenantid
        $tenant = (get-tenants -IncludeErrors | Where-Object -Property defaultDomainName -EQ $tenantid).customerId
        if ($cmdParams) {
            $Params = $cmdParams
        }
        else {
            $Params = @{}
        }
        $ExoBody = ConvertTo-Json -Depth 5 -InputObject @{
            CmdletInput = @{
                CmdletName = $cmdlet
                Parameters = $Params
            }
        }
        if (!$Anchor) {
            if ($cmdparams.Identity) { $Anchor = $cmdparams.Identity }
            if ($cmdparams.anr) { $Anchor = $cmdparams.anr }
            if ($cmdparams.User) { $Anchor = $cmdparams.User }

            if (!$Anchor -or $useSystemMailbox) {
                $OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantid -NoAuthCheck $NoAuthCheck | Where-Object -Property isInitial -EQ $true).id
                $anchor = "UPN:SystemMailbox{8cc370d3-822a-4ab8-a926-bb94bd0641a9}@$($OnMicrosoft)"

            }
        }
        Write-Host "Using $Anchor"
        $Headers = @{
            Authorization             = "Bearer $($token.access_token)"
            Prefer                    = 'odata.maxpagesize = 1000'
            'parameter-based-routing' = $true
            'X-AnchorMailbox'         = $anchor

        }
        try {
            $ReturnedData = Invoke-RestMethod "https://outlook.office365.com/adminapi/beta/$($tenant)/InvokeCommand" -Method POST -Body $ExoBody -Headers $Headers -ContentType 'application/json; charset=utf-8'
        }
        catch {
            $ErrorMess = $($_.Exception.Message)
            $ReportedError = ($_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue)
            $Message = if ($ReportedError.error.details.message) {
                $ReportedError.error.details.message
            }
            elseif ($ReportedError.error.message) { $ReportedError.error.message }
            else { $ReportedError.error.innererror.internalException.message }
            if ($null -eq $Message) { $Message = $ErrorMess }
            throw $Message
        }
        return $ReturnedData.value
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function Read-JwtAccessDetails {
    <#
    .SYNOPSIS
    Parse Microsoft JWT access tokens

    .DESCRIPTION
    Extract JWT access token details for verification

    .PARAMETER Token
    Token to get details for

    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    # Default token object
    $TokenDetails = [PSCustomObject]@{
        AppId             = ''
        AppName           = ''
        Audience          = ''
        AuthMethods       = ''
        IPAddress         = ''
        Name              = ''
        Scope             = ''
        TenantId          = ''
        UserPrincipalName = ''
    }

    if (!$Token.Contains('.') -or !$token.StartsWith('eyJ')) { return $TokenDetails }

    # Get token payload
    $tokenPayload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    while ($tokenPayload.Length % 4) {
        $tokenPayload = '{0}=' -f $tokenPayload
    }

    # Convert base64 to json to object
    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
    $TokenObj = $tokenArray | ConvertFrom-Json

    # Convert token details to human readable
    $TokenDetails.AppId = $TokenObj.appid
    $TokenDetails.AppName = $TokenObj.app_displayname
    $TokenDetails.Audience = $TokenObj.aud
    $TokenDetails.AuthMethods = $TokenObj.amr
    $TokenDetails.IPAddress = $TokenObj.ipaddr
    $TokenDetails.Name = $TokenObj.name
    $TokenDetails.Scope = $TokenObj.scp -split ' '
    $TokenDetails.TenantId = $TokenObj.tid
    $TokenDetails.UserPrincipalName = $TokenObj.upn

    return $TokenDetails
}

function Get-CIPPMSolUsers {
    [CmdletBinding()]
    param (
        [string]$tenant
    )
    $AADGraphtoken = (Get-GraphToken -scope 'https://graph.windows.net/.default')
    $tenantid = (get-tenants | Where-Object -Property defaultDomainName -EQ $tenant).customerId
    $TrackingGuid = (New-Guid).GUID
    $LogonPost = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/MsolConnect</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">$($TrackingGuid)</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><MsolConnect xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version4</b:BecVersion><b:TenantId i:nil="true"/><b:VerifiedDomain i:nil="true"/></request></MsolConnect></s:Body></s:Envelope>
"@
    $DataBlob = (Invoke-RestMethod -Method POST -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -ContentType 'application/soap+xml; charset=utf-8' -Body $LogonPost).envelope.header.BecContext.DataBlob.'#text'

    $MSOLXML = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/ListUsers</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><BecContext xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><DataBlob xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$DataBlob</DataBlob><PartitionId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">2</PartitionId></BecContext><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">4e6cb653-c968-4a3a-8a11-2c8919218aeb</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><ListUsers xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version16</b:BecVersion><b:TenantId>$($tenantid)</b:TenantId><b:VerifiedDomain i:nil="true"/><b:UserSearchDefinition xmlns:c="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration"><c:PageSize>500</c:PageSize><c:SearchString i:nil="true"/><c:SortDirection>Ascending</c:SortDirection><c:SortField>None</c:SortField><c:AccountSku i:nil="true"/><c:BlackberryUsersOnly i:nil="true"/><c:City i:nil="true"/><c:Country i:nil="true"/><c:Department i:nil="true"/><c:DomainName i:nil="true"/><c:EnabledFilter i:nil="true"/><c:HasErrorsOnly i:nil="true"/><c:IncludedProperties i:nil="true" xmlns:d="http://schemas.microsoft.com/2003/10/Serialization/Arrays"/><c:IndirectLicenseFilter i:nil="true"/><c:LicenseReconciliationNeededOnly i:nil="true"/><c:ReturnDeletedUsers i:nil="true"/><c:State i:nil="true"/><c:Synchronized i:nil="true"/><c:Title i:nil="true"/><c:UnlicensedUsersOnly i:nil="true"/><c:UsageLocation i:nil="true"/></b:UserSearchDefinition></request></ListUsers></s:Body></s:Envelope>
"@
    $userlist = do {
        if ($null -eq $page) {
            $Page = (Invoke-RestMethod -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -Method post -Body $MSOLXML -ContentType 'application/soap+xml; charset=utf-8').envelope.body.ListUsersResponse.listusersresult.returnvalue
            $Page.results.user
        }
        else {
            $Page = (Invoke-RestMethod -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -Method post -Body $MSOLXML -ContentType 'application/soap+xml; charset=utf-8').envelope.body.NavigateUserResultsResponse.NavigateUserResultsResult.returnvalue
            $Page.results.user
        }
        $MSOLXML = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/NavigateUserResults</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><BecContext xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><DataBlob xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$DataBlob</DataBlob><PartitionId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">130</PartitionId></BecContext><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">$($TrackingGuid)</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><NavigateUserResults xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version16</b:BecVersion><b:TenantId>$($tenantid)</b:TenantId><b:VerifiedDomain i:nil="true"/><b:ListContext>$($page.listcontext)</b:ListContext><b:PageToNavigate>Next</b:PageToNavigate></request></NavigateUserResults></s:Body></s:Envelope>
"@
    } until ($page.IsLastPage -eq $true -or $null -eq $page)
    return $userlist
}

function New-DeviceLogin {
    [CmdletBinding()]
    param (
        [string]$clientid,
        [string]$scope,
        [switch]$FirstLogon,
        [string]$device_code,
        [string]$TenantId
    )
    $encodedscope = [uri]::EscapeDataString($scope)
    if ($FirstLogon) {
        if ($TenantID) {
            $ReturnCode = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($TenantID)/oauth2/v2.0/devicecode" -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid"

        }
        else {
            $ReturnCode = Invoke-RestMethod -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode' -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid"
        }
    }
    else {
        $Checking = Invoke-RestMethod -SkipHttpErrorCheck -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token' -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid&grant_type=device_code&device_code=$($device_code)"
        if ($checking.refresh_token) {
            $ReturnCode = $Checking
        }
        else {
            $returncode = $Checking.error
        }
    }
    return $ReturnCode
}

function New-passwordString {
    [CmdletBinding()]
    param (
        [int]$count = 12
    )
    Set-Location (Get-Item $PSScriptRoot).FullName
    $SettingsTable = Get-CippTable -tablename 'Settings'
    $PasswordType = (Get-CIPPAzDataTableEntity @SettingsTable).passwordType
    if ($PasswordType -eq 'Correct-Battery-Horse') {
        $Words = Get-Content .\words.txt
        (Get-Random -InputObject $words -Count 4) -join '-'
    }
    else {
        -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count $count)
    }
}

function New-GraphBulkRequest {
    Param(
        $tenantid,
        $NoAuthCheck,
        $scope,
        $asapp,
        $Requests
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp

        $URL = 'https://graph.microsoft.com/beta/$batch'

        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant) {
            $Tenant = @{
                GraphErrorCount = 0
                LastGraphError  = $null
                PartitionKey    = 'TenantFailed'
                RowKey          = 'Failed'
            }
        }
        try {
            $ReturnedData = for ($i = 0; $i -lt $Requests.count; $i += 20) {
                $req = @{}
                # Use select to create hashtables of id, method and url for each call
                $req['requests'] = ($Requests[$i..($i + 19)])
                Invoke-RestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ($req | ConvertTo-Json -Depth 10)
            }

            foreach ($MoreData in $ReturnedData.Responses | Where-Object { $_.body.'@odata.nextLink' }) {
                Write-Host 'Getting more'
                $AdditionalValues = New-GraphGetRequest -ComplexFilter -uri $MoreData.body.'@odata.nextLink' -tenantid $TenantFilter -NoAuthCheck:$NoAuthCheck
                $NewValues = [System.Collections.Generic.List[PSCustomObject]]$MoreData.body.value
                $AdditionalValues | ForEach-Object { $NewValues.add($_) }
                $MoreData.body.value = $NewValues
            }

        }
        catch {
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
            if ($Message -eq $null) { $Message = $($_.Exception.Message) }
            if ($Message -ne 'Request not applicable to target tenant.') {
                $Tenant.LastGraphError = $Message
                $Tenant.GraphErrorCount++
                Update-AzDataTableEntity @TenantsTable -Entity $Tenant
            }
            throw $Message
        }

        $Tenant.LastGraphError = ''
        Update-AzDataTableEntity @TenantsTable -Entity $Tenant

        return $ReturnedData.responses
    }
    else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}

function Get-GraphBulkResultByID ($Results, $ID, [switch]$Value) {
    if ($Value) {
    ($Results | Where-Object { $_.id -eq $ID }).body.value
    }
    else {
        ($Results | Where-Object { $_.id -eq $ID }).body
    }
}
