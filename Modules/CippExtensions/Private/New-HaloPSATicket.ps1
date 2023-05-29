function New-HaloPSATicket {
  [CmdletBinding()]
  param (
    $title,
    $description,
    $client
  )
  #Get Halo PSA Token based on the config we have.
  $Table = Get-CIPPTable -TableName Extensionsconfig
  $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA

  $token = Get-HaloToken -configuration $Configuration
  #use the token to create a new ticket in HaloPSA
  $body = @"
[
  {
    "files": null,
    "usertype": 1,
    "userlookup": {
      "id": -1,
      "lookupdisplay": "Enter Details Manually"
    },
    "client_id": $client,
    "site_id": null,
    "user_name": null,
    "reportedby": null,
    "summary": "$($title)",
    "details_html": "$description",
    "donotapplytemplateintheapi": true,
    "attachments": [
      
    ]
  }
]
"@
  Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Tickets" -ContentType 'application/json' -Method Post -Body $body -Headers @{Authorization = "Bearer $($token.access_token)" }

}