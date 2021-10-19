function Get-GraphToken($tenantid, $scope, $AsApp, $AppID, $refreshToken, $ReturnRefresh) {
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }

    $AuthBody = @{
        client_id     = $ENV:ApplicationId
        client_secret = $ENV:ApplicationSecret
        scope         = $Scope
        refresh_token = $ENV:RefreshToken
        grant_type    = "refresh_token"
                    
    }
    if ($asApp -eq $true) {
        $AuthBody = @{
            client_id     = $ENV:ApplicationId
            client_secret = $ENV:ApplicationSecret
            scope         = $Scope
            grant_type    = "client_credentials"
        }
    }

    if ($null -ne $AppID -and $null -ne $refreshToken) {
        $AuthBody = @{
            client_id     = $appid
            refresh_token = $RefreshToken
            scope         = $Scope
            grant_type    = "refresh_token"
        }
    }

    if (!$tenantid) { $tenantid = $env:tenantid }
    $AccessToken = (Invoke-RestMethod -Method post -Uri "https://login.microsoftonline.com/$($tenantid)/oauth2/v2.0/token" -Body $Authbody -ErrorAction Stop)
    if ($ReturnRefresh) { $header = $AccessToken } else { $header = @{ Authorization = "Bearer $($AccessToken.access_token)" } }

    return $header
}

function New-GraphGetRequest ($uri, $tenantid, $scope, $AsApp) {
    $TenantList = Get-Content 'Tenants.cache.json'  -ErrorAction SilentlyContinue | ConvertFrom-Json
    $Skiplist = Get-Content "ExcludedTenants" | ConvertFrom-Csv -Delimiter "|" -Header "Name", "User", "Date"

    if ($tenantid -ne $null -and $tenantid -in $($Skiplist.name)) {
        return "Not allowed. Tenant is in exclusion list."
    }
    if ($scope -eq "ExchangeOnline") { 
        $Headers = Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenantid
    }
    else {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
    }
    Write-Verbose "Using $($uri) as url"
    $nextURL = $uri
    #not a fan of this, have to reconsider and change. Seperate function?
    if ($tenantid -in $tenantlist.defaultdomainname -or $uri -like "https://graph.microsoft.com/beta/contracts?`$top=999" -or $uri -like "*/customers/*") {
        $ReturnedData = do {
            $Data = (Invoke-RestMethod -Uri $nextURL -Method GET -Headers $headers -ContentType "application/json; charset=utf-8")
            if ($data.value) { $data.value } else { ($Data) }
            $nextURL = $data.'@odata.nextLink'
        } until ($null -eq $NextURL)
        return $ReturnedData   
    }
    else {
        Write-Error "Not allowed. You cannot manage your own tenant or tenants not under your scope" 
    }
}       

function New-GraphPOSTRequest ($uri, $tenantid, $body, $type, $scope, $AsApp) {
    $Skiplist = Get-Content "ExcludedTenants" | ConvertFrom-Csv -Delimiter "|" -Header "Name", "User", "Date"
    $TenantList = Get-Content 'Tenants.cache.json'  -ErrorAction SilentlyContinue | ConvertFrom-Json

    if ($tenantid -ne $null -and $tenantid -in $($Skiplist.name)) {
        return "Not allowed. Tenant is in exclusion list."
    }
    $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
    Write-Verbose "Using $($uri) as url"
    if (!$type) {
        $type = 'POST'
    }
    #not a fan of this, have to reconsider and change. Seperate function?
    if ($tenantid -in $tenantlist.defaultdomainname -or $uri -like "*/contracts*" -or $uri -like "*/customers/*") {
        $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType "application/json; charset=utf-8")
        return $ReturnedData 
    }
    else {
        Write-Error "Not allowed. You cannot manage your own tenant or tenants not under your scope" 
    }
}
Function Log-request ($message, $tenant, $API, $user, $sev) {
    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    $date = (Get-Date).ToString('s')
    $LogMutex = New-Object System.Threading.Mutex($false, "LogMutex")
    if (!$username) { $username = "CIPP" }
    if (!$tenant) { $tenant = "None" }
    $logdata = "$($date)|$($tenant)|$($API)|$($message)|$($username)|$($sev)"
    if ($LogMutex.WaitOne(1000)) {
        $logdata | Out-File -Append -path "$((Get-Date).ToString('MMyyyy')).log"
    }
    $LogMutex.ReleaseMutex()
}
function convert-skuname($skuname, $skuID) {
    $ConvertTable = Import-Csv Conversiontable.csv
    if ($skuname) { $ReturnedName = ($ConvertTable | Where-Object { $_.String_Id -eq $skuname } | Select-Object -Last 1).'Product_Display_Name' }
    if ($skuID) { $ReturnedName = ($ConvertTable | Where-Object { $_.guid -eq $skuid } | Select-Object -Last 1).'Product_Display_Name' }
    if ($ReturnedName) { return $ReturnedName } else { return $skuname, $skuID }
}
