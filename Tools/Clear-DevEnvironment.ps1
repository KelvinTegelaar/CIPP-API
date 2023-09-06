$EnvironmentVariables = @('TenantId', 'ApplicationId', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'PartnerTenantAvailable')
ForEach ($Key in $EnvironmentVariables) {
    [Environment]::SetEnvironmentVariable($Key, $null)
}