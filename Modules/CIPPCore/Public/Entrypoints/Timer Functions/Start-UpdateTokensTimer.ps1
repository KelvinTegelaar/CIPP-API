function Start-UpdateTokensTimer {
    <#
    .SYNOPSIS
    Start the Update Tokens Timer
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    if ($PSCmdlet.ShouldProcess('Start-UpdateTokensTimer', 'Starting Update Tokens Timer')) {
        Write-Information 'Starting Update Tokens Timer'
        Write-Information "Getting new refresh token for $($env:TenantId)"
        # Get the current universal time in the default string format.
        $currentUTCtime = (Get-Date).ToUniversalTime()
        try {
            $Refreshtoken = (Get-GraphToken -ReturnRefresh $true).Refresh_token
            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $Table = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                if ($Secret) {
                    $Secret.RefreshToken = $Refreshtoken
                    Add-AzDataTableEntity @Table -Entity $Secret -Force
                } else {
                    Write-LogMessage -API 'Update Tokens' -message 'Could not update refresh token. Will try again in 7 days.' -sev 'CRITICAL'
                }
            } else {
                $KV = Get-CippKeyVaultName
                if ($Refreshtoken) {
                    Set-CippKeyVaultSecret -VaultName $KV -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
                } else {
                    Write-LogMessage -API 'Update Tokens' -message 'Could not update refresh token. Will try again in 7 days.' -sev 'CRITICAL'
                }
            }
        } catch {
            Write-Warning "Error updating refresh token $($_.Exception.Message)."
            Write-Information ($_.InvocationInfo.PositionMessage)
            Write-LogMessage -API 'Update Tokens' -message 'Error updating refresh token, see Log Data for details. Will try again in 7 days.' -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        }

        # Credentials before this run, so the changes it makes can be acknowledged to the credential monitor.
        # Unknown before-state acknowledges nothing, so no unrelated change is swallowed.
        $CredentialsBefore = $null
        try { $CredentialsBefore = @((Get-CIPPSAMCredentials).Credentials | ForEach-Object keyId) } catch { }

        # Check application secret expiration for $env:ApplicationId and generate a new application secret if expiration is within 30 days.
        try {
            $AppId = $env:ApplicationID
            $AppRegistration = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')?`$select=id,passwordCredentials,servicePrincipalLockConfiguration" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
            $PasswordCredentials = $AppRegistration.passwordCredentials | Sort-Object -Property endDateTime -Descending
            # Judge expiry on this instance's own secret when it is tracked; other instances or
            # integrations may hold newer secrets on the same app.
            $ConfigTable = Get-CIPPTable -tablename 'Config'
            $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
            $TrackedCredential = if ($AppCache.SecretKeyId) { $PasswordCredentials | Where-Object { $_.keyId -eq $AppCache.SecretKeyId } | Select-Object -First 1 }
            $LastPasswordCredential = $TrackedCredential ?? ($PasswordCredentials | Select-Object -First 1)

            try {
                $AppPolicyStatus = Update-AppManagementPolicy
                Write-Information $AppPolicyStatus.PolicyAction
            } catch {
                Write-Warning "Error updating app management policy $($_.Exception.Message)."
                Write-Information ($_.InvocationInfo.PositionMessage)
            }

            if ($env:CertificateAuthMode) {
                # Certificate-exclusive mode: CIPP authenticates with the SAM certificate, so never
                # generate a client secret. Doing so would fail on tenants blocking password addition,
                # or silently re-create a secret on a secret-less install. The certificate is renewed below.
                Write-Information "Certificate authentication is enabled for $AppId; skipping client secret generation."
            } elseif ($LastPasswordCredential.endDateTime -lt (Get-Date).AddDays(30).ToUniversalTime()) {
                Write-Information "Application secret for $AppId is expiring soon. Generating a new application secret."
                try {
                    $AppSecret = Update-CIPPSAMSecret -ApplicationObjectId $AppRegistration.id -DisplayName 'UpdateTokens' -Source 'ScheduledRotation' -APIName 'Update Tokens'
                    Write-Information "New application secret generated for $AppId. Expiration date: $($AppSecret.EndDateTime)."
                } catch {
                    Write-LogMessage -API 'Update Tokens' -message "Failed to rotate the application secret for $AppId, see Log Data for details. Will try again in 7 days." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
                }
            } else {
                Write-Information "Application secret for $AppId is valid until $($LastPasswordCredential.endDateTime). No need to generate a new application secret."
            }

            # Clean up expired application secrets
            $ExpiredSecrets = $PasswordCredentials | Where-Object { $_.endDateTime -lt (Get-Date).ToUniversalTime() }
            if ($ExpiredSecrets.Count -gt 0) {
                Write-Information "Found $($ExpiredSecrets.Count) expired application secrets for $AppId. Removing them."
                foreach ($Secret in $ExpiredSecrets) {
                    try {
                        New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)/removePassword" -Body "{`"keyId`":`"$($Secret.keyId)`"}" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                        Write-LogMessage -API 'Update Tokens' -tenant 'Global' -message "Scheduled cleanup: removed expired CIPP-SAM client secret '$($Secret.displayName)' (keyId $($Secret.keyId)) from $AppId." -sev 'Alert'
                    } catch {
                        Write-LogMessage -API 'Update Tokens' -message "Error removing expired application secret with keyId $($Secret.keyId), see Log Data for details." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
                    }
                }
            } else {
                Write-Information "No expired application secrets found for $AppId."
            }

            if (!$AppRegistration.servicePrincipalLockConfiguration.isEnabled) {
                Write-Warning "Service principal lock configuration is not enabled for $AppId"
                $Body = @{
                    servicePrincipalLockConfiguration = @{
                        isEnabled     = $true
                        allProperties = $true
                    }
                } | ConvertTo-Json
                New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/v1.0/applications/$($AppRegistration.id)" -Body $Body -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                Write-Information "Service principal lock configuration has been enabled for application $AppId."
                Write-LogMessage -API 'Update Tokens' -message "Service principal lock configuration has been enabled for application $AppId." -sev 'Info'
            }

        } catch {
            Write-Warning "Error updating application secret $($_.Exception.Message)."
            Write-Information ($_.InvocationInfo.PositionMessage)
            Write-LogMessage -API 'Update Tokens' -message 'Error updating application secret, will try again in 7 days' -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        }

        # Create or renew the SAM certificate when missing or within 30 days of expiry
        try {
            $CertResult = Update-CIPPSAMCertificate -ErrorAction Stop
            if ($CertResult.Renewed) {
                Write-Information "SAM certificate renewed. Thumbprint: $($CertResult.Thumbprint), expires: $($CertResult.NotAfter), storage mode: $($CertResult.StorageMode)"
            }
        } catch {
            Write-Warning "Error updating SAM certificate $($_.Exception.Message)."
            Write-Information ($_.InvocationInfo.PositionMessage)
            Write-LogMessage -API 'Update Tokens' -message 'Error updating SAM certificate, will try again in 7 days' -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        }

        # Rotate the CIPP-SSO client secret within 30 days of expiry. Isolated so SSO failures never block SAM work.
        try {
            $MigrationTable = Get-CIPPTable -tablename 'SSOMigration'
            $Migration = Get-CIPPAzDataTableEntity @MigrationTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'"
            $SSOAppId = $Migration.AppId
            if (-not $SSOAppId) {
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $DevTable = Get-CIPPTable -tablename 'DevSecrets'
                    $SSOAppId = (Get-CIPPAzDataTableEntity @DevTable -Filter "PartitionKey eq 'SSO' and RowKey eq 'SSO'").SSOAppId
                } else {
                    try { $SSOAppId = Get-CippKeyVaultSecret -Name 'SSOAppId' -AsPlainText -ErrorAction Stop } catch { $SSOAppId = $null }
                }
            }
            if ($SSOAppId) {
                $SSOApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$SSOAppId')?`$select=id,passwordCredentials" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                $NewestSSOSecret = $SSOApp.passwordCredentials | Sort-Object -Property endDateTime -Descending | Select-Object -First 1
                if ($NewestSSOSecret.endDateTime -lt (Get-Date).AddDays(30).ToUniversalTime()) {
                    try {
                        $NewSSOSecret = Add-CIPPSSOAppSecret -ObjectId $SSOApp.id -AppId $SSOAppId
                        Set-CIPPSSOStoredCredentials -AppSecret $NewSSOSecret
                        Write-LogMessage -API 'Update Tokens' -tenant 'Global' -message "Scheduled rotation: new CIPP-SSO client secret created for $SSOAppId (previous secret keyId $($NewestSSOSecret.keyId) expires $($NewestSSOSecret.endDateTime)). No action needed beyond the restart below." -sev 'Alert'
                        # A restart from a timer would interrupt running work; the previous secret stays valid until it expires.
                        Write-LogMessage -API 'Update Tokens' -tenant 'Global' -message "Restart required: CIPP keeps signing in with the previous CIPP-SSO secret until the instance restarts. Restart before $($NewestSSOSecret.endDateTime) to apply the new secret." -sev 'Warning'
                    } catch {
                        Write-LogMessage -API 'Update Tokens' -tenant 'Global' -message "Scheduled rotation: failed to rotate the CIPP-SSO client secret for $SSOAppId, will try again in 7 days." -sev 'Error' -LogData (Get-CippException -Exception $_)
                    }
                }
            }
        } catch {
            Write-Warning "Error checking the CIPP-SSO client secret $($_.Exception.Message)."
        }

        # Get new refresh token for each direct added tenant
        $TenantList = Get-Tenants -IncludeAll | Where-Object { $_.Excluded -eq $false -and $_.delegatedPrivilegeStatus -eq 'directTenant' }
        if ($TenantList.Count -eq 0) {
            Write-Information 'No direct tenants found for refresh token update.'
        } else {
            Write-Information "Found $($TenantList.Count) direct tenant(s) for refresh token update."
            foreach ($Tenant in $TenantList) {
                try {
                    Write-Information "Updating refresh token for tenant $($Tenant.displayName) - $($Tenant.customerId)"
                    $Refreshtoken = (Get-GraphToken -ReturnRefresh $true -TenantId $Tenant.customerId).Refresh_token
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                        $Table = Get-CIPPTable -tablename 'DevSecrets'
                        $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                        if ($Secret) {
                            $name = $Tenant.customerId -replace '-', '_'
                            $Secret | Add-Member -MemberType NoteProperty -Name $name -Value $Refreshtoken -Force
                            Add-AzDataTableEntity @Table -Entity $Secret -Force
                        } else {
                            Write-Warning "Could not update refresh token for tenant $($Tenant.displayName) ($($Tenant.customerId))."
                            Write-LogMessage -API 'Update Tokens' -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message "Could not update refresh token for tenant $($Tenant.displayName). Will try again in 7 days." -sev 'CRITICAL'
                        }
                    } else {
                        if ($Refreshtoken) {
                            $name = $Tenant.customerId
                            Set-CippKeyVaultSecret -VaultName $KV -Name $name -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
                        } else {
                            Write-Warning "Could not update refresh token for tenant $($Tenant.displayName) ($($Tenant.customerId))."
                            Write-LogMessage -API 'Update Tokens' -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message "Could not update refresh token for tenant $($Tenant.displayName). Will try again in 7 days." -sev 'CRITICAL'
                        }
                    }
                } catch {
                    Write-LogMessage -API 'Update Tokens' -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message "Error updating refresh token for tenant $($Tenant.displayName), see Log Data for details. Will try again in 7 days." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
                }
            }
        }

        # Changes this run made still alert, worded as scheduled so they do not read as a compromise.
        try {
            $CredentialsAfter = Get-CIPPSAMCredentials
            $Changed = if ($null -ne $CredentialsBefore) { @(Compare-Object -ReferenceObject $CredentialsBefore -DifferenceObject @($CredentialsAfter.Credentials | ForEach-Object keyId) | ForEach-Object InputObject) } else { @() }
            $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge $Changed -AcknowledgeNote 'Changed by this CIPP instance during the scheduled token update.' -CredentialState $CredentialsAfter
        } catch { Write-Warning "Could not refresh the SAM credential snapshot: $($_.Exception.Message)" }

        # Write an information log with the current time.
        Write-Information "UpdateTokens completed: $currentUTCtime"
    }
}
