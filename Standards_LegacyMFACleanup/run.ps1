param($tenant)

try {
    $AADGraphtoken = (Get-GraphToken -scope 'https://graph.windows.net/.default')
    $tenantid = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant).customerId

    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)
        $SecDefaults = $SecureDefaultsState.IsEnabled
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Security default state: $SecDefaults" -sev Debug
    }
    catch {
        $SecDefaults = $false
    }
    
    try {
        $AllUsersCAPolicy = (New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$filter=(grantControls/builtInControls/any(b:b eq 'mfa') or grantControls/customAuthenticationFactors/any(c:c eq 'RequireDuoMfa')) and state eq 'enabled' and conditions/users/includeUsers/any(u:u eq 'All')&`$count=true" -ComplexFilter -tenantid $tenant).displayName
        Write-LogMessage -API 'Standards' -tenant $tenant -message "All users CA policy: $AllUsersCAPolicy" -sev Debug

        if ($AllUsersCAPolicy) {
            $AADPremiumUsers = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/?`$select=id,userPrincipalName&`$filter=assignedPlans/any(c:c/service eq 'AADPremiumService' and c/capabilityStatus eq 'Enabled')&`$count=true" -tenantid $tenant -ComplexFilter).userPrincipalName
            Write-LogMessage -API 'Standards' -tenant $tenant -message "AAD Premium Users: $($AADPremiumUsers -join ', ')" -sev Debug
        }
    }
    catch {
        $AllUsersCAPolicy = $false
    }

    if ($SecDefaults -or $AllUsersCAPolicy) {

        $TrackingGuid = (New-Guid).GUID
        $LogonPost = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/MsolConnect</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">$($TrackingGuid)</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><MsolConnect xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version4</b:BecVersion><b:TenantId i:nil="true"/><b:VerifiedDomain i:nil="true"/></request></MsolConnect></s:Body></s:Envelope>
"@
        $DataBlob = (Invoke-RestMethod -Method POST -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -ContentType 'application/soap+xml; charset=utf-8' -Body $LogonPost).envelope.header.BecContext.DataBlob.'#text'
        $Users = Get-CIPPMSolUsers -tenant $tenant | Where-Object { ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $_.UserPrincipalName -notlike 'Sync_*') }
        foreach ($user in $users) {
            #Write-Host $user.UserPrincipalName

            if ($AllUsersCAPolicy -and $AADPremiumUsers -notcontains $user.UserPrincipalName) {
                Write-Host "Skipping user $($user.UserPrincipalName) does not have AAD Premium"
                continue
            }

            $MSOLXML = @"
<?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/SetUser</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" i:nil="true" /></UserIdentityHeader><BecContext xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><DataBlob xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($DataBlob)</DataBlob><PartitionId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">94</PartitionId></BecContext><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">$TrackingGuid</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><SetUser xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version16</b:BecVersion><b:TenantId>$($tenantid)</b:TenantId><b:VerifiedDomain i:nil="true" /><b:User xmlns:c="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration"><c:ObjectId>$($User.ObjectID)</c:ObjectId><c:StrongAuthenticationRequirements><c:StrongAuthenticationRequirement><c:RelyingParty>*</c:RelyingParty><c:RememberDevicesNotIssuedBefore>0001-01-01T00:00:00</c:RememberDevicesNotIssuedBefore><c:State>Disabled</c:State></c:StrongAuthenticationRequirement></c:StrongAuthenticationRequirements></b:User></request></SetUser></s:Body></s:Envelope>
"@
            $SetMFA = (Invoke-RestMethod -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -Method post -Body $MSOLXML -ContentType 'application/soap+xml; charset=utf-8')
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Cleaned up per user MFA.' -sev Info
    }
    else {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unable to clean up per user MFA, tenant does not have Security Defaults or an all users CA policy requiring MFA' -sev Error
    }
}
catch {
    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to clean up (legacy) per user MFA: $($_.exception.message)"
}