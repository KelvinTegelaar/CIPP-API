param($tenant)

try {
  $Test = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/security/alerts' -tenantid $tenant.defaultDomainName

  $ReturnObject = @()

  $ReturnObject = foreach ($alert in $test) {
    $Stuff = [PSCustomObject]@{
      Tenant = $tenant.defaultDomainName
      Id     = $alert.Id
      Title  = $alert.Title
    }
    $Stuff
  } 
}
catch {
  Write-Host "$($_.Exception.Message)"
}

$ReturnObject