function Invoke-ExecBackupReplicationConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName Config
    $Scopes = @('Core', 'Tenant')

    # Returns whether a SAS URL secret currently exists for the given scope, without ever exposing it.
    function Get-ReplicationSecretIsSet {
        param([string]$Scope)
        try {
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'BackupReplication$Scope' and RowKey eq 'BackupReplication$Scope'").SASUrl
                if ([string]::IsNullOrWhiteSpace($Secret)) {
                    return $null
                }
                return "SentToKeyVault"
            }
            else {
                $Secret = Get-CippKeyVaultSecret -Name "BackupReplication$Scope" -AsPlainText
                if ([string]::IsNullOrWhiteSpace($Secret)) {
                    return $null
                }
                return "SentToKeyVault"
            }
        } catch {
            return $null
        }
    }

    $results = try {
        if ($Request.Query.List) {
            $Output = @{}
            foreach ($Scope in $Scopes) {
                $Config = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'BackupReplication' and RowKey eq '$Scope'"
                $Output[$Scope] = @{
                    Enabled = [bool]($Config.Enabled)
                    IsSet   = Get-ReplicationSecretIsSet -Scope $Scope
                }
            }
            [pscustomobject]$Output
        } else {
            $BackupType = $Request.Body.BackupType
            if ($BackupType -notin $Scopes) {
                throw "BackupType must be one of: $($Scopes -join ', ')"
            }

            $SASUrl = $Request.Body.SASUrl
            $Enabled = if ($null -ne $Request.Body.Enabled) { [bool]$Request.Body.Enabled } else { $true }

            # Only update the stored secret when a real new value is supplied (the UI sends the
            # 'SentToKeyVault' sentinel when the existing, masked secret is left untouched).
            if (-not [string]::IsNullOrWhiteSpace($SASUrl) -and $SASUrl -ne 'SentToKeyVault') {
                $ParsedUri = $SASUrl -as [uri]
                if (-not $ParsedUri -or $ParsedUri.Query -notmatch 'sig=') {
                    throw 'SAS URL must contain a SAS token (sig=...)'
                }

                # Confirm the SAS actually grants write+create by writing and removing a tiny probe blob.
                $guid = [guid]::NewGuid().ToString()
                $UrlParts = $SASUrl -split '\?', 2
                $BaseUrl = $UrlParts[0].TrimEnd('/')
                $ProbeUrl = "$BaseUrl/.cipp-replication-test-$guid`?$($UrlParts[1])"
                try {
                    $null = Invoke-CIPPRestMethod -Uri $ProbeUrl -Method 'PUT' -Body "cipp-replication-test-$guid" -ContentType 'text/plain' -Headers @{ 'x-ms-blob-type' = 'BlockBlob' }
                    try { $null = Invoke-CIPPRestMethod -Uri $ProbeUrl -Method 'DELETE' -Headers @{} } catch { }
                } catch {
                    $ProbeError = Get-CippException -Exception $_
                    throw "SAS URL validation failed (could not write to the container): $($ProbeError.NormalizedError)"
                }

                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = [PSCustomObject]@{
                        'PartitionKey' = "BackupReplication$BackupType"
                        'RowKey'       = "BackupReplication$BackupType"
                        'SASUrl'       = $SASUrl
                    }
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
                }
                else {
                    Set-CippKeyVaultSecret -Name "BackupReplication$BackupType" -SecretValue (ConvertTo-SecureString -String $SASUrl -AsPlainText -Force) | Out-Null
                }
            }

            $Config = @{
                'PartitionKey' = 'BackupReplication'
                'RowKey'       = $BackupType
                'Enabled'      = $Enabled
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Config -Force | Out-Null

            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Updated $BackupType backup replication settings (Enabled: $Enabled)" -Sev 'Info'
            "Successfully updated $BackupType backup replication settings"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to update backup replication configuration: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        "Failed to update configuration: $($ErrorMessage.NormalizedError)"
    }

    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
