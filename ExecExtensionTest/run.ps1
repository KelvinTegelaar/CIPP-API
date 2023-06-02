using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Table = Get-CIPPTable -TableName Extensionsconfig
$Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json)
# Interact with query parameters or the body of the request.
try {
      switch ($Request.query.extensionName) {
            "HaloPSA" {
                  $token = Get-HaloToken -configuration $Configuration.HaloPSA
                  $Results = [pscustomobject]@{"Results" = "Succesfully Connected to HaloPSA" }
            }
            "Gradient" {
                  $Tenants = Get-Tenants
                  $GradientToken = Get-GradientToken -Configuration $Configuration.Gradient
                  $ExistingAccounts = (Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method GET -Headers $GradientToken)
                  $NewAccounts = $Tenants | Where-Object defaultDomainName -NotIn $ExistingAccounts.id | ForEach-Object {
                        [PSCustomObject]@{
                              name        = $_.displayName
                              description = $_.defaultDomainName
                              id          = $_.defaultDomainName
                        }
                  } | ConvertTo-Json -Depth 10
                  Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/accounts' -Method POST -Headers $GradientToken -Body $NewAccounts -ContentType 'application/json'
                  #setting the integration to active

                  $ExistingIntegrations = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization' -Method GET -Headers $GradientToken
                  if ($ExistingIntegrations.Status -ne "active") {
                        $ActivateRequest = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/organization/status/active' -Method PATCH -Headers $GradientToken
                  }
                  $Results = [pscustomobject]@{"Results" = "Succesfully Connected to Gradient" }

            }

      }
}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed to connect: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })