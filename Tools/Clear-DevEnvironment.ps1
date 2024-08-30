$EnvironmentVariables = @('TenantID', 'ApplicationID', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'PartnerTenantAvailable', 'SetFromProfile')
ForEach ($Key in $EnvironmentVariables) {
    [Environment]::SetEnvironmentVariable($Key, $null)
}
