param($tenant)

try {
  $Stuff = [System.Collections.Generic.List[PSCustomObject]]@()
  $Test = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/incidents' -tenantid $tenant.defaultDomainName -AsApp $true

  foreach ($incident in $test) {
    # Generate a GUID and do some stuff to make sure it is a legal name
    $GUID = "divid" + (New-Guid).Guid.Replace('-', '')

    $Stuff.Add([PSCustomObject]@{
        Tenant         = $tenant.defaultDomainName
        GUID           = $GUID
        Id             = $incident.id
        Status         = $incident.status
        IncidentUrl    = $incident.incidentWebUrl
        RedirectId     = $incident.redirectIncidentId
        DisplayName    = $incident.displayName
        Created        = $incident.createdDateTime
        Updated        = $incident.lastUpdateDateTime
        AssignedTo     = $incident.assignedTo
        Classification = $incident.classification
        Determination  = $incident.determination
        Severity       = $incident.severity
        Tags           = $incident.tags
        Comments       = $incident.comments
      })
  }

  $Stuff
}
catch {
  $Stuff.Add([PSCustomObject]@{
      Tenant         = $tenant.defaultDomainName
      GUID           = $GUID
      Id             = $incident.id
      Status         = $incident.status
      IncidentUrl    = $incident.incidentWebUrl
      RedirectId     = $incident.redirectIncidentId
      DisplayName    = $incident.displayName
      Created        = $incident.createdDateTime
      Updated        = $incident.lastUpdateDateTime
      AssignedTo     = $incident.assignedTo
      Classification = $incident.classification
      Determination  = $incident.determination
      Severity       = $incident.severity
      Tags           = $incident.tags
      Comments       = $incident.comments
    })
  $Stuff
}