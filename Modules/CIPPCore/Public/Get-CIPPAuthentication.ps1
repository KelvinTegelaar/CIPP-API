
function Get-CIPPAuthentication {
    [CmdletBinding()]
    param (
        $APIName = 'Get Keyvault Authentication',
        [switch]$Force
    )
    $Variables = @('ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken')

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-AzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if (!$Secret) {
                throw 'Development variables not set'
            }
            foreach ($Var in $Variables) {
                if ($Secret.$Var) {
                    Set-Item -Path env:$Var -Value $Secret.$Var -Force -ErrorAction Stop
                }
            }
            Write-Host "Got secrets from dev storage. ApplicationID: $env:ApplicationID"
        } else {
            $keyvaultname = Get-CippKeyVaultName
            $Variables | ForEach-Object {
                Set-Item -Path env:$_ -Value (Get-CippKeyVaultSecret -VaultName $keyvaultname -Name $_ -AsPlainText -ErrorAction Stop) -Force
            }
        }
        # Set before certificate handling: Update-CIPPSAMCertificate goes through
        # Get-GraphToken, which re-enters this function when SetFromProfile is unset
        $env:SetFromProfile = $true

        # Preload the SAM certificate PFX alongside the other credentials, provisioning it
        # when it does not exist yet. Non-fatal: auth must succeed even when certificate
        # handling fails; the weekly token update retries provisioning.
        try {
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                if ($Secret.SAMCertificate) {
                    $env:SAMCertificate = $Secret.SAMCertificate
                }
            } else {
                try {
                    $SAMCertificate = Get-CippKeyVaultSecret -VaultName $keyvaultname -Name 'SAMCertificate' -AsPlainText -ErrorAction Stop
                    if ($SAMCertificate) {
                        $env:SAMCertificate = $SAMCertificate
                    }
                } catch {
                    Write-Information "SAM certificate not found in storage: $($_.Exception.Message)"
                }
            }

            if (-not $env:SAMCertificate) {
                # First run on this instance: provision the certificate now.
                # Set-CIPPSAMCertificate refreshes $env:SAMCertificate on success.
                Write-Information 'No SAM certificate found, provisioning one now'
                $CertResult = Update-CIPPSAMCertificate -ErrorAction Stop
                Write-LogMessage -message "Provisioned SAM certificate during authentication load. Thumbprint: $($CertResult.Thumbprint), storage mode: $($CertResult.StorageMode)" -Sev 'Info' -API 'CIPP Authentication'
            }
        } catch {
            Write-LogMessage -message 'Could not preload or provision the SAM certificate. It will be retried by the weekly token update.' -Sev 'Warning' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
        }

        Write-LogMessage -message 'Reloaded authentication data from KeyVault' -Sev 'debug' -API 'CIPP Authentication'

        return $true
    } catch {
        Write-LogMessage -message 'Could not retrieve keys from Keyvault' -Sev 'CRITICAL' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
        return $false
    }
}
