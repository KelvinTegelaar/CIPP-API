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
                if ($env:MSI_SECRET) {
                    Disable-AzContextAutosave -Scope Process | Out-Null
                    $null = Connect-AzAccount -Identity
                    $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
                    $null = Set-AzContext -SubscriptionId $SubscriptionId
                }
                $KV = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
                if ($Refreshtoken) {
                    Set-AzKeyVaultSecret -VaultName $KV -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
                } else {
                    Write-LogMessage -API 'Update Tokens' -message 'Could not update refresh token. Will try again in 7 days.' -sev 'CRITICAL'
                }
            }
        } catch {
            Write-Warning "Error updating refresh token $($_.Exception.Message)."
            Write-Information ($_.InvocationInfo.PositionMessage)
            Write-LogMessage -API 'Update Tokens' -message 'Error updating refresh token, see Log Data for details. Will try again in 7 days.' -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
        }

        # Check application secret expiration for $env:ApplicationId and generate a new application secret if expiration is within 30 days.
        try {
            $AppId = $env:ApplicationID
            $PasswordCredentials = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')?`$select=id,passwordCredentials" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
            # sort by latest expiration date and get the first one
            $LastPasswordCredential = $PasswordCredentials.passwordCredentials | Sort-Object -Property endDateTime -Descending | Select-Object -First 1
            if ($LastPasswordCredential.endDateTime -lt (Get-Date).AddDays(30).ToUniversalTime()) {
                Write-Information "Application secret for $AppId is expiring soon. Generating a new application secret."
                $AppSecret = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/applications/$($PasswordCredentials.id)/addPassword" -Body '{"passwordCredential":{"displayName":"UpdateTokens"}}' -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                Write-Information "New application secret generated for $AppId. Expiration date: $($AppSecret.endDateTime)."
            } else {
                Write-Information "Application secret for $AppId is valid until $($LastPasswordCredential.endDateTime). No need to generate a new application secret."
            }

            if ($AppSecret) {
                if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                    $Table = Get-CIPPTable -tablename 'DevSecrets'
                    $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                    $Secret.ApplicationSecret = $AppSecret.secretText
                    Add-AzDataTableEntity @Table -Entity $Secret -Force
                } else {
                    Set-AzKeyVaultSecret -VaultName $KV -Name 'ApplicationSecret' -SecretValue (ConvertTo-SecureString -String $AppSecret.secretText -AsPlainText -Force)
                }
                Write-LogMessage -API 'Update Tokens' -message "New application secret generated for $AppId. Expiration date: $($AppSecret.endDateTime)." -sev 'INFO'
            }

            # Clean up expired application secrets
            $ExpiredSecrets = $PasswordCredentials.passwordCredentials | Where-Object { $_.endDateTime -lt (Get-Date).ToUniversalTime() }
            if ($ExpiredSecrets.Count -gt 0) {
                Write-Information "Found $($ExpiredSecrets.Count) expired application secrets for $AppId. Removing them."
                foreach ($Secret in $ExpiredSecrets) {
                    try {
                        New-GraphPostRequest -type DELETE -uri "https://graph.microsoft.com/v1.0/applications/$($PasswordCredentials.id)/removePassword" -Body "{`"keyId`":`"$($Secret.keyId)`"}" -NoAuthCheck $true -AsApp $true -ErrorAction Stop
                        Write-Information "Removed expired application secret with keyId $($Secret.keyId)."
                    } catch {
                        Write-LogMessage -API 'Update Tokens' -message "Error removing expired application secret with keyId $($Secret.keyId), see Log Data for details." -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
                    }
                }
            } else {
                Write-Information "No expired application secrets found for $AppId."
            }
        } catch {
            Write-Warning "Error updating application secret $($_.Exception.Message)."
            Write-Information ($_.InvocationInfo.PositionMessage)
            Write-LogMessage -API 'Update Tokens' -message 'Error updating application secret, will try again in 7 days' -sev 'CRITICAL' -LogData (Get-CippException -Exception $_)
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
                            Set-AzKeyVaultSecret -VaultName $KV -Name $name -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
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

        # Write an information log with the current time.
        Write-Information "UpdateTokens completed: $currentUTCtime"
    }
}
