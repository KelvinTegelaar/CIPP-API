$EnvironmentVariables = @('TenantId', 'ApplicationId', 'ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage')
ForEach ($Key in $EnvironmentVariables) {
    [Environment]::SetEnvironmentVariable($Key, $null)
}