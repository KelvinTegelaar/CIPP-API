using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$PerUserMFA = Get-MsolUser -all -TenantId $TenantFilter | Where-Object {$_.isLicensed -eq ”TRUE”} | Select-Object DisplayName,isLicensed,UserPrincipalName,@{N="MFA Status"; E={if( $_.StrongAuthenticationRequirements.State -ne $null) {$_.StrongAuthenticationRequirements.State} else { "Disabled"}}}


try{
  $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails" -tenantid $TenantFilter | Select-Object userPrincipalName, isMfaRegistered
}catch {
 $GraphRequest = "null"
}


$MFAComplier = foreach ($user in $PerUserMFA ) {
  [PSCustomObject]@{
      'DisplayName'                                          = $user.DisplayName
      'UserPrincipalName'                                     = $user.userPrincipalName
      "PerUserMFA"                                          = $user.'MFA Status'
      "CAPolicySecurityDefaults"        = ($GraphRequest | Where-Object { $_.UserPrincipalName -eq $user.userPrincipalName}).isMfaRegistered
      "isLicensed"                                            = $user.isLicensed
  }

$response = $MFAComplier | select-object @{ Name = 'UPN'; Expression = { $_.UserPrincipalName } },
@{ Name = 'displayName'; Expression = { $_.DisplayName} },
@{ Name = 'PerUserMFA'; Expression = { $_.PerUserMFA } },
@{ Name = 'MFARegisteredviaCAPolicy/SecurityDefaults'; Expression = { $_.CAPolicySecurityDefaults } },
@{ Name = 'isLicensed'; Expression = { $_.isLicensed} }

}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($response)
    })