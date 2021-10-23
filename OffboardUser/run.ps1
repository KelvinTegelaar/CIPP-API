using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Username = $request.body.user
$Tenantfilter = $request.body.tenantfilter
if ($username -eq $null) { exit }
$userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id

$results = switch ($request.body) {
    { "ResetPass" -eq 'true' } { 
        $password = -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count 12)
        $passwordProfile = @"
                {"passwordProfile": { "forceChangePasswordNextSignIn": true, "password": "$password" }}'
"@ 
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $TenantFilter -type PATCH -body $passwordProfile  -verbose
        "The new password is $NewPass"
    }
    { "RemoveGroups" -eq 'true' } { 
        $Groups = (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/GetMemberGroups" -tenantid $tenantFilter -type POST -body  '{"securityEnabledOnly": false}').value | ForEach-Object {
            $RemoveRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($userid)/`$ref" -tenantid $tenantFilter -type DELETE -body '' -Verbose
            $_
        }
        "Removed the user from the following groups: $($Groups -join ",")"
    }

    { "HideFromGAL" -eq 'true' } {
        $HideRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $tenantFilter -type PATCH -body '{"showInAddressList": false}' -verbose
        "Hidden from address list"
    }
    { "DisableUser" -eq 'true' } {
        $DisableUser = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($userid)" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":false}'  -verbose
        "Disabled user account"
    }
    { "ConvertToShared" -eq 'true' } { 
        $upn = "notrequired@notrequired.com" 
        $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenantFilter).Authorization -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
        $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenantFilter)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ea Stop
        Import-PSSession $session -ea Stop -AllowClobber -CommandName "Set-Mailbox"
        $Mailbox = Set-mailbox -identity $userid -type Shared -ea Stop
        Remove-PSSession $session
        "Converted to Shared Mailbox"
    }
    { "OnedriveAccess" -ne "" } { 
        $UserSharepoint = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/drive" -AsApp $true -tenantid $tenantFilter).weburl -replace "/Documents"
        $GainAccessJson = '{"SecondaryContact":"'+ $request.body.OnedriveAccess +'","IsCurrentUserPersonalSiteAdmin":false,"IsDelegatedAdmin":true,"UserPersonalSiteUrl":"'+$UserSharepoint+'"}'
        #$GainAccessJson = '{"SharingCapabilitiesForTenant":3,"SecondaryContactDisplayName":null,"errorState":false,"SecondaryContact":"' + $request.body.OnedriveAccess + '","IsCurrentUserPersonalSiteAdmin":false,"IsUserSpecificQuota":false,"StoragePercentageUse":0.12,"SharingCapabilities":3,"ExceptionMessage":null,"OrphanedPersonalSitesRetentionPeriod":2492,"IsDelegatedAdmin":false,"LitigationHoldPresent":false,"TenantMaxQuotaLimitInGB":5120,"UserPersonalSiteUrl":"' + $UserSharepoint + '","StorageQuotaLimit":5120}'
        $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
        $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
        $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
        $OwnershipOnedrive = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/users/setSecondaryOwner' -Body $GainAccessJson -Method POST -Headers @{
            Authorization            = "Bearer $($token.access_token)";
            "x-ms-client-request-id" = [guid]::NewGuid().ToString();
            "x-ms-client-session-id" = [guid]::NewGuid().ToString()
            'x-ms-correlation-id'    = [guid]::NewGuid()
            'X-Requested-With'       = 'XMLHttpRequest' 
        }
        "Users Onedrive url is $UserSharepoint. Access has been given to $($request.body.onedriveaccess)"
    }
    { "AccessNoAutomap" -eq 'true' } { "Resetpass" }
    { "AccessAutomap" -eq 'true' } { "Resetpass" }
    
    
    { "removeLicenses" -eq 'true' } {
        $CurrentLicenses = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter).assignedlicenses.skuid
        $LicensesToRemove = if ($CurrentLicenses) { ConvertTo-Json @( $CurrentLicenses) } else { "[]" }
        $LicenseBody = '{"addLicenses": [], "removeLicenses": ' + $LicensesToRemove + '}'
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/assignlicense" -tenantid $tenantFilter -type POST -body $LicenseBody -verbose

    }

    { "Deleteuser" -eq 'true' } {
        $DeleteRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -type DELETE -tenant $TenantFilter
        "Deleted the user account"
    }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
