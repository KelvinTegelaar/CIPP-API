$headers = Get-GradientToken
$body = ConvertTo-Json 
$response = Invoke-RestMethod -Uri 'https://app.usegradient.com/api/vendor-api/service' -Method POST -Headers $headers