using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$UserID = $Request.Query.UserID


$TenantFilter = $Request.Query.TenantFilter
try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Request.Query.UserID)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)  
    $CASRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/CasMailbox('$UserID')" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
    $MailRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$UserID')" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
    $FetchParam = @{
        anr = $MailRequest.PrimarySmtpAddress
    }
    $MailboxDetailedRequest = New-ExoRequest -TenantID $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams $FetchParam
    try {
        $Archive = New-ExoRequest -TenantID $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams $FetchParam
        if ($Archive.ArchiveStatus -eq "Active") {
            $ArchiveEnabled = $True 
        }
        else {
            $ArchiveEnabled = $False
        }

        $FetchParam = @{
            Identity = $MailRequest.PrimarySmtpAddress
            Archive  = $true
        }

        $ArchiveSize = New-ExoRequest -TenantID $TenantFilter -cmdlet 'Get-MailboxStatistics' -cmdParams $FetchParam
    }
    catch {
        $ArchiveEnabled = $False
        $ArchiveSize = @{
            TotalItemSize = "0"
            ItemCount     = "0"
        }
    }
    $FetchParam = @{
        SenderAddress = $MailRequest.PrimarySmtpAddress
    }
    $BlockedSender = New-ExoRequest -TenantID $TenantFilter -cmdlet 'Get-BlockedSenderAddress' -cmdParams $FetchParam
    if ($BlockedSender) {
        $BlockedForSpam = $True
    }
    else {
        $BlockedForSpam = $False
    }
    $StatsRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$($MailRequest.PrimarySmtpAddress)')/Exchange.GetMailboxStatistics()" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
    $PermsRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$($MailRequest.PrimarySmtpAddress)')/MailboxPermission" -Tenantid $tenantfilter -scope ExchangeOnline -noPagination $true
    $PermsRequest2 = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Recipient('$base64IdentityParam')?`$expand=RecipientPermission&isEncoded=true" -Tenantid $tenantfilter -scope ExchangeOnline 

}
catch {
    Write-Error "Failed Fetching Data $($_.Exception.message): $($_.InvocationInfo.ScriptLineNumber)"
}

$ParsedPerms = foreach ($Perm in $PermsRequest, $PermsRequest2.RecipientPermission) {

    if ($perm.Trustee) {
        $perm | Where-Object Trustee | ForEach-Object { [PSCustomObject]@{
                User         = $_.Trustee
                AccessRights = $_.accessRights -join ', ' 
            }
        }
            
    }
    if ($perm.PermissionList) {
        $perm |  Where-Object User | ForEach-Object { [PSCustomObject]@{
                User         = $_.User
                AccessRights = $_.PermissionList.accessRights -join ', '
            }        
        }
    }
}

$forwardingaddress = if ($MailboxDetailedRequest.ForwardingAddress) {
    $MailboxDetailedRequest.ForwardingAddress 
}
elseif ($MailboxDetailedRequest.ForwardingSmtpAddress -and $MailboxDetailedRequest.ForwardingAddress) {
    $MailboxDetailedRequest.ForwardingAddress + ' ' + $MailboxDetailedRequest.ForwardingSmtpAddress
}
else {
    $MailboxDetailedRequest.ForwardingSmtpAddress 
}

if ($ArchiveSize) { 
$GraphRequest = [ordered]@{
    ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
    ForwardingAddress        = $ForwardingAddress
    LitiationHold            = $MailboxDetailedRequest.LitigationHoldEnabled
    HiddenFromAddressLists   = $MailboxDetailedRequest.HiddenFromAddressListsEnabled
    EWSEnabled               = $CASRequest.EwsEnabled
    MailboxMAPIEnabled       = $CASRequest.MAPIEnabled
    MailboxOWAEnabled        = $CASRequest.OWAEnabled
    MailboxImapEnabled       = $CASRequest.ImapEnabled
    MailboxPopEnabled        = $CASRequest.PopEnabled
    MailboxActiveSyncEnabled = $CASRequest.ActiveSyncEnabled
    Permissions              = $ParsedPerms
    ProhibitSendQuota        = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendQuota -split ' GB')[0], 2)
    ProhibitSendReceiveQuota = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendReceiveQuota -split ' GB')[0], 2)
    ItemCount                = [math]::Round($StatsRequest.ItemCount, 2)
    TotalItemSize            = [math]::Round($StatsRequest.TotalItemSize / 1Gb, 2)
    TotalArchiveItemSize     = $ArchiveSize.totalItemSize.split('(')[0]
    TotalArchiveItemCount    = [math]::Round($ArchiveSize.ItemCount, 2)
    BlockedForSpam           = $BlockedForSpam
    ArchiveMailBox           = $ArchiveEnabled
    AutoExpandingArchive     = $Archive.AutoExpandingArchiveEnabled
}
}
else {
    $GraphRequest = [ordered]@{
        ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
        ForwardingAddress        = $ForwardingAddress
        LitiationHold            = $MailboxDetailedRequest.LitigationHoldEnabled
        HiddenFromAddressLists   = $MailboxDetailedRequest.HiddenFromAddressListsEnabled
        EWSEnabled               = $CASRequest.EwsEnabled
        MailboxMAPIEnabled       = $CASRequest.MAPIEnabled
        MailboxOWAEnabled        = $CASRequest.OWAEnabled
        MailboxImapEnabled       = $CASRequest.ImapEnabled
        MailboxPopEnabled        = $CASRequest.PopEnabled
        MailboxActiveSyncEnabled = $CASRequest.ActiveSyncEnabled
        Permissions              = $ParsedPerms
        ProhibitSendQuota        = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendQuota -split ' GB')[0], 2)
        ProhibitSendReceiveQuota = [math]::Round([float]($MailboxDetailedRequest.ProhibitSendReceiveQuota -split ' GB')[0], 2)
        ItemCount                = [math]::Round($StatsRequest.ItemCount, 2)
        TotalItemSize            = [math]::Round($StatsRequest.TotalItemSize / 1Gb, 2)
        TotalArchiveItemSize     = 0
        TotalArchiveItemCount    = 0
        BlockedForSpam           = $BlockedForSpam
        ArchiveMailBox           = $ArchiveEnabled
        AutoExpandingArchive     = $Archive.AutoExpandingArchiveEnabled
    }
}


#$GraphRequest = [ordered]@{
#    Connectivity  = $CASRequest
#    Mailbox       = $MailRequest
#    MailboxDetail = $MailboxDetailedRequest
#    Stats         = $StatsRequest
#    Permissions   = $ParsedPerms
#    Result        = $Result
#}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })