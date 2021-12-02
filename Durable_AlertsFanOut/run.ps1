param($tenant)

try {
  $Stuff = [System.Collections.Generic.List[PSCustomObject]]@()
  $Test = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/security/alerts' -tenantid $tenant.defaultDomainName -AsApp $true

  foreach ($alert in $test) {
    # Generate a GUID and do some stuff to make sure it is a legal name
    $GUID = "divid" + (New-Guid).Guid.Replace('-','')

    $Stuff.Add([PSCustomObject]@{
      Tenant = $tenant.defaultDomainName
      GUID = $GUID
      Id     = $alert.Id
      Title  = $alert.Title
      Category = $alert.category
      EventDateTime = $alert.eventDateTime
      Severity = $alert.Severity
      Status = $alert.Status
      RawResult = $($Test | ? {$_.Id -eq $alert.Id})
    })
  }

  $Stuff
}
catch {
  Write-Host "$($_.Exception.Message)"
  $Stuff.Add([PSCustomObject]@{
    Tenant = $tenant.defaultDomainName
    GUID = $GUID
    Id     = ""
    Title  = ""
    Category = ""
    EventDateTime = ""
    Severity = ""
    Status = ""
    RawResult = ""
  })
}