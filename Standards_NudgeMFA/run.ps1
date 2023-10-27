param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.NudgeMFA
if (!$Setting) {
    $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.NudgeMFA
}
Write-Output $setting
$status = if ($Setting.enable -and $Setting.disable) {
    Write-LogMessage -API "Standards" -tenant $tenant -message "You cannot both enable and disable the Nudge MFA setting" -sev Error
    Exit
}
elseif ($setting.enable) { "enabled" } else { "disabled" }
Write-Output $status
try {
    $Body = (New-GraphGetRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy")
    $body.registrationEnforcement.authenticationMethodsRegistrationCampaign.state = $status
    $body = ConvertTo-Json -Depth 10 -InputObject ($body | Select-Object registrationEnforcement)
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy" -Type patch -Body $body -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "$status Authenticator App Nudge" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to $status Authenticator App Nudge: $($_.exception.message)" -sev Error
}