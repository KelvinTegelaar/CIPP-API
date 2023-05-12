using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

try {
	$GraphRequestList = @{
		Endpoint = 'policies/crossTenantAccessPolicy/partners'
		Tenant   = $Request.Query.TenantFilter
	}
	$Partners = Get-GraphRequestList @GraphRequestList

	$GraphRequest = foreach ($Partner in $Partners) {
		if ($Partner.tenantId) {
			$PartnerInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$($Partner.tenantId)')" -noauthcheck $true

			$Partner | Select-Object @{n = 'displayName'; e = { $PartnerInfo.displayName } }, @{n = 'federationBrandName'; e = { $PartnerInfo.federationBrandName } }, @{n = 'defaultDomainName'; e = { $PartnerInfo.defaultDomainName } }, *
		}
	}
} catch {
	$GraphRequest = @()
}

$StatusCode = [HttpStatusCode]::OK

$results = [PSCustomObject]@{
	Results = @($GraphRequest)
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
		StatusCode = $StatusCode
		Body       = $results
	})
