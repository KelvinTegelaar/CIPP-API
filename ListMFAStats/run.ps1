using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
# $PerUserMFA = Get-MsolUser -all -TenantId 1685b7a8-3883-44b8-b613-b9328c67c798 | Where-Object {$_.isLicensed -eq "TRUE"} | Select-Object DisplayName,isLicensed,UserPrincipalName,@{N="MFAStatus"; E={if( $_.StrongAuthenticationRequirements.State -ne $null) {$_.StrongAuthenticationRequirements.State} else { "Disabled"}}}


try{
  $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails" -tenantid $TenantFilter | Select-Object @{ Name = 'UPN'; Expression = { $_.userPrincipalName } },
  @{ Name = 'mfaregistered'; Expression = { $_.isMfaRegistered } } 

}catch {
 $GraphRequest = "null"
}


# $response= foreach ($user in $PerUserMFA ) {
#   [PSCustomObject]@{
#       DisplayName= $user.DisplayName
#       UserPrincipalName= $user.userPrincipalName
#       PerUserMFA= $user.MFAStatus
#       CAPolicySecurityDefaults= ($GraphRequest | Where-Object { $_.UserPrincipalName -eq $user.userPrincipalName}).isMfaRegistered
#       isLicensed= $user.isLicensed
#   }
# }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })