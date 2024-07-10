function New-GradientAlert {
    [CmdletBinding()]
    param (
        $title,
        $description,
        $client
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Gradient
    #creating accounts in Gradient
    try {
        $GradientToken = Get-GradientToken -Configuration $Configuration
        $ExistingAccounts = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method GET -Headers $GradientToken) | Where-Object id -EQ $client
        $NewAccounts = ConvertTo-Json -Depth 10 -InputObject @([PSCustomObject]@{
                name        = $_.displayName
                description = $_.defaultDomainName
                id          = $_.defaultDomainName
            })
        if ($ExistingAccounts -eq $null) {
            Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method POST -Headers $GradientToken -Body $NewAccounts -ContentType 'application/json'
        }
        #Send the alert
        $body = @"
        {"priority":1,"status":1,"title":"$title","description":"$description","alertId":"$(New-Guid)"}
"@
        $AlertId = Invoke-RestMethod -Uri "https://app.usegradient.com/api/vendor-api/alerting/$($client)" -Method POST -Headers $GradientToken -Body $body -ContentType 'application/json'
        #check if the message is actually sent, if not, abort and log. check url: https://app.usegradient.com/api/vendor-api/alerting/debug/{messageId}
        $AlertStatus = Invoke-RestMethod -Uri "https://app.usegradient.com/api/vendor-api/alerting/debug/$($AlertId.messageId)" -Method GET -Headers $GradientToken
        if ($AlertStatus.status -eq "failed") {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Failed to create ticket in Gradient API. Error: $($AlertStatus.errors)" -Sev "Error" -tenant $client

        }
       
    } 
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Failed to create ticket in Gradient API. Error: $($_.Exception.Message)" -Sev "Error" -tenant "GradientAPI"
    }


}