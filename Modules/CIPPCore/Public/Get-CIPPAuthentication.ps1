
function Get-CIPPAuthentication {
    [CmdletBinding()]
    param (
        $APIName = 'Get Keyvault Authentication',
        [switch]$Force
    )
    $Variables = @('ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken')

    try {
        $IsDevMode = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'
        if ($IsDevMode) {
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
        # TenantID must be the tenant GUID: a domain name (contoso.onmicrosoft.com)
        # works for token requests but breaks API integrations that compare or store
        # tenant ids. Resolve a domain to its GUID via the unauthenticated OpenID
        # metadata endpoint. Skip the deployment template's placeholder value —
        # fresh deployments hold 'tenantId' until the setup wizard writes real
        # secrets (same placeholder set as Initialize-CIPPAuth).
        $GuidPattern = '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
        $PlaceholderPattern = '^(LongApplicationId|AppSecret|RefreshToken|tenantId)$'
        if ($env:TenantID -and $env:TenantID -notmatch $GuidPattern -and $env:TenantID -notmatch $PlaceholderPattern) {
            $StoredTenantID = $env:TenantID
            try {
                $OpenIdConfig = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$StoredTenantID/v2.0/.well-known/openid-configuration" -ErrorAction Stop
                $ResolvedTenantID = ($OpenIdConfig.issuer -split '/')[3]
                if ($ResolvedTenantID -notmatch $GuidPattern) {
                    throw "OpenID metadata for '$StoredTenantID' did not contain a tenant GUID (issuer: $($OpenIdConfig.issuer))"
                }
                $env:TenantID = $ResolvedTenantID
                Write-LogMessage -message "The TenantID secret is set to domain name '$StoredTenantID' - resolved to tenant GUID $ResolvedTenantID." -Sev 'Warning' -API 'CIPP Authentication'

                # Fix the stored secret so every future load gets the GUID directly.
                # Best-effort: this session already has the resolved value.
                if ($IsDevMode) {
                    try {
                        $Secret | Add-Member -MemberType NoteProperty -Name 'TenantID' -Value $ResolvedTenantID -Force
                        $null = Add-AzDataTableEntity @Table -Entity $Secret -Force
                        Write-LogMessage -message "Updated the TenantID in the DevSecrets table from '$StoredTenantID' to tenant GUID $ResolvedTenantID." -Sev 'Info' -API 'CIPP Authentication'
                    } catch {
                        Write-LogMessage -message 'Could not update the TenantID in the DevSecrets table - it will be re-resolved on every authentication load.' -Sev 'Warning' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
                    }
                } elseif ($keyvaultname) {
                    try {
                        $null = Set-CippKeyVaultSecret -VaultName $keyvaultname -Name 'TenantID' -SecretValue (ConvertTo-SecureString -String $ResolvedTenantID -AsPlainText -Force) -ErrorAction Stop
                        Write-LogMessage -message "Updated the 'TenantID' Key Vault secret from '$StoredTenantID' to tenant GUID $ResolvedTenantID." -Sev 'Info' -API 'CIPP Authentication'
                    } catch {
                        Write-LogMessage -message "Could not update the 'TenantID' Key Vault secret to the tenant GUID - it will be re-resolved on every authentication load until the secret is updated manually." -Sev 'Warning' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
                    }
                }
            } catch {
                Write-LogMessage -message "The TenantID secret ('$StoredTenantID') is not a GUID and could not be resolved to one. API integrations may misbehave until the 'tenantid' Key Vault secret is set to the tenant GUID." -Sev 'Error' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
            }
        }

        # Set before certificate handling: Update-CIPPSAMCertificate goes through
        # Get-GraphToken, which re-enters this function when SetFromProfile is unset
        $env:SetFromProfile = $true

        # Preload the SAM certificate PFX alongside the other credentials, provisioning it
        # when it does not exist yet. Non-fatal: auth must succeed even when certificate
        # handling fails; the weekly token update retries provisioning.
        try {
            if ($IsDevMode) {
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

            if (-not $env:SAMCertificate -and $env:SAMCertProvisionAttempted -ne 'true') {
                # First run on this instance: provision the certificate now, at most once per
                # process. The guard also breaks a recursion loop: Update-CIPPSAMCertificate
                # calls Get-GraphToken, which re-enters this function when the AppCache
                # ApplicationId does not match the environment.
                # Set-CIPPSAMCertificate refreshes $env:SAMCertificate on success.
                $env:SAMCertProvisionAttempted = 'true'
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
