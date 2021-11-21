using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
#Let's hack the provisioning API to get per user MFA
$AADGraphtoken = (Get-GraphToken -scope 'https://graph.windows.net/.default')
$tenantid = ((Get-Content 'tenants.cache.json' | ConvertFrom-Json) | Where-Object -Property DefaultDomainName -EQ $Request.Query.TenantFilter).CustomerID
$TrackingGuid = New-Guid
$LogonPost = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/MsolConnect</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">$($TrackingGuid)</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><MsolConnect xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version4</b:BecVersion><b:TenantId i:nil="true"/><b:VerifiedDomain i:nil="true"/></request></MsolConnect></s:Body></s:Envelope>
"@
$DataBlob = (Invoke-RestMethod -Method POST -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -ContentType 'application/soap+xml; charset=utf-8' -Body $LogonPost).envelope.header.BecContext.DataBlob.'#text'

$MSOLXML = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing"><s:Header><a:Action s:mustUnderstand="1">http://provisioning.microsoftonline.com/IProvisioningWebService/ListUsers</a:Action><a:MessageID>urn:uuid:$TrackingGuid</a:MessageID><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo><UserIdentityHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BearerToken xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$($AADGraphtoken['Authorization'])</BearerToken><LiveToken i:nil="true" xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService"/></UserIdentityHeader><BecContext xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><DataBlob xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">$DataBlob</DataBlob><PartitionId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">2</PartitionId></BecContext><ClientVersionHeader xmlns="http://provisioning.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ClientId xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">50afce61-c917-435b-8c6d-60aa5a8b8aa7</ClientId><Version xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">1.2.183.57</Version></ClientVersionHeader><ContractVersionHeader xmlns="http://becwebservice.microsoftonline.com/" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><BecVersion xmlns="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService">Version47</BecVersion></ContractVersionHeader><TrackingHeader xmlns="http://becwebservice.microsoftonline.com/">4e6cb653-c968-4a3a-8a11-2c8919218aeb</TrackingHeader><a:To s:mustUnderstand="1">https://provisioningapi.microsoftonline.com/provisioningwebservice.svc</a:To></s:Header><s:Body><ListUsers xmlns="http://provisioning.microsoftonline.com/"><request xmlns:b="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration.WebService" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:BecVersion>Version16</b:BecVersion><b:TenantId>$($tenantid)</b:TenantId><b:VerifiedDomain i:nil="true"/><b:UserSearchDefinition xmlns:c="http://schemas.datacontract.org/2004/07/Microsoft.Online.Administration"><c:PageSize>500</c:PageSize><c:SearchString i:nil="true"/><c:SortDirection>Ascending</c:SortDirection><c:SortField>None</c:SortField><c:AccountSku i:nil="true"/><c:BlackberryUsersOnly i:nil="true"/><c:City i:nil="true"/><c:Country i:nil="true"/><c:Department i:nil="true"/><c:DomainName i:nil="true"/><c:EnabledFilter i:nil="true"/><c:HasErrorsOnly i:nil="true"/><c:IncludedProperties i:nil="true" xmlns:d="http://schemas.microsoft.com/2003/10/Serialization/Arrays"/><c:IndirectLicenseFilter i:nil="true"/><c:LicenseReconciliationNeededOnly i:nil="true"/><c:ReturnDeletedUsers i:nil="true"/><c:State i:nil="true"/><c:Synchronized i:nil="true"/><c:Title i:nil="true"/><c:UnlicensedUsersOnly i:nil="true"/><c:UsageLocation i:nil="true"/></b:UserSearchDefinition></request></ListUsers></s:Body></s:Envelope>
"@
$Users = (Invoke-RestMethod -Uri 'https://provisioningapi.microsoftonline.com/provisioningwebservice.svc' -Method post -Body $MSOLXML -ContentType 'application/soap+xml; charset=utf-8').envelope.body.ListUsersResponse.listusersresult.returnvalue.results.user
$SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Request.query.TenantFilter ).IsEnabled
$CAState = New-Object System.Collections.ArrayList
try {
    $ExcludeAllUsers = New-Object System.Collections.ArrayList
    $ExcludeSpecific = New-Object System.Collections.ArrayList
    $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $Request.query.TenantFilter )

    foreach ($Policy in $CAPolicies) {
        if (($policy.grantControls.builtincontrols -eq 'mfa') -or ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa')) {
            if ($Policy.conditions.applications.includeApplications -ne 'All') {
                Write-Host $Policy.conditions.applications.includeApplications
                $CAState.Add('Specific Applications') | Out-Null
                $ExcludeSpecific = $Policy.conditions.users.excludeUsers
                continue
            }
            if ($Policy.conditions.users.includeUsers -eq 'All') {
                $CAState.Add('All Users') | Out-Null
                $ExcludeAllUsers = $Policy.conditions.users.excludeUsers
                continue
            }
        } 
    }
}
catch {}
if (($CAState | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) { $CAState.Add('None') | Out-Null }
Try {
    $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $Request.query.TenantFilter)
}
catch {
    $MFARegistration = $null
}
# Interact with query parameters or the body of the request.
$GraphRequest = $Users | ForEach-Object {
    $UserCAState = New-Object System.Collections.ArrayList
    foreach ($CA in $CAState) {
        if ($CA -eq 'All Users') {
            if ($ExcludeAllUsers -contains $_.ObjectId) { $UserCAState.Add('Excluded from All Users') | Out-Null }
            else { $UserCAState.Add($CA) | Out-Null }
        }
        elseif ($CA -eq 'Specific Applications') {
            if ($ExcludeSpecific -contains $_.ObjectId) { $UserCAState.Add('Excluded from Specific Applications') | Out-Null }
            else { $UserCAState.Add($CA) | Out-Null }
        }
        else {
            $UserCAState.Add($CA) | Out-Null
        }
    }

    $PerUser = if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -ne $null) { $_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state } else { 'Disabled' }
    $AccountState = if ($_.BlockCredential -eq $true) { $false } else { $true }

    $MFARegUser = if (($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered -eq $null) { $false } else { ($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered }
    [PSCustomObject]@{
        UPN             = $_.UserPrincipalName
        AccountEnabled  = $AccountState
        PerUser         = $PerUser
        MFARegistration = $MFARegUser
        CoveredByCA     = ($UserCAState -join ', ')
        CoveredBySD     = $SecureDefaultsState
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })