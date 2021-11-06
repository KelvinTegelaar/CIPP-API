# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Config = Get-Content "SendNotifcations\Config.json" | ConvertFrom-Json

if (!$Config) { 
  "Done - No config active"
  exit 
}

$Settings = $Request.Body.psobject.properties.name
$logdate = (Get-Date).ToString('MMyyyy')
$Currentlog = Get-Content "Logs\$($logdate).log" | ConvertFrom-Csv -Header "DateTime", "Tenant", "API", "Message", "User", "Severity" -Delimiter "|" | Where-Object { [datetime]$_.Datetime -gt (Get-Date).AddMinutes(-31) -and $_.api -in $Settings -and $_.Severity -ne "debug" }


if ($Config.email -ne "" -and $null -ne $CurrentLog) {
  $HTMLLog = ($CurrentLog | ConvertTo-Html -frag) -replace "<table>", "<table class=blueTable>" | Out-String
  $JSONBody = @"
                    {
                        "message": {
                          "subject": "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-31))",
                          "body": {
                            "contentType": "HTML",
                            "content": "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log:<br><br>
      <style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>
                            
                            $($HTMLLog)
                            
                            "
                          },
                          "toRecipients": [
                            {
                              "emailAddress": {
                                "address": "$($config.email)"
                              }
                            }
                          ]
                        },
                        "saveToSentItems": "false"
                      }
"@
  New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/me/sendMail" -tenantid $env:TenantID -type POST -body ($JSONBody)
}



if ($Config.webhook -ne "" -and $null -ne $CurrentLog) {
  switch -wildcard ($config.Webhook) {

    "*webhook.office.com*" {
      $Log = $Currentlog | ConvertTo-Html -frag | Out-String
      $JSonBody = "{`"text`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. <br><br>$Log`"}" 
    }

    "*slack.com*" {
      $Log = $Currentlog | Format-Table | Out-String
      $JSonBody = "{`"text`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. $Log`"}" 
    }

    "*discord.com*" {
      $Log = $Currentlog | ConvertTo-Html -frag | Out-String
      $JSonBody = "{`"content`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. $Log`"}" 
    }
  }
  Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType "Application/json" -Body $JSONBody
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

 