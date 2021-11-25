param($tenant)

try {
  $Test = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/security/alerts' -tenantid $tenant.defaultDomainName
}
catch {
  Write-Host "$($_.Exception.Message)"
}

$Test