function Invoke-ExecUpdateRefreshToken {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $KV = $env:WEBSITE_DEPLOYMENT_ID

    try {
        # Handle refresh token update
        #make sure we get the latest authentication:
        $auth = Get-CIPPAuthentication
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"

            if ($env:TenantID -eq $Request.body.tenantId) {
                $Secret | Add-Member -MemberType NoteProperty -Name 'RefreshToken' -Value $Request.body.refreshtoken -Force
                # Set environment variable to make it immediately available
                Set-Item -Path env:RefreshToken -Value $Request.body.refreshtoken -Force
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.body.tenantId)"
                $name = $Request.body.tenantId -replace '-', '_'
                $secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.body.refreshtoken -Force
                # Set environment variable to make it immediately available
                Set-Item -Path env:$name -Value $Request.body.refreshtoken -Force
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            if ($env:TenantID -eq $Request.body.tenantId) {
                Set-CippKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                # Set environment variable to make it immediately available
                Set-Item -Path env:RefreshToken -Value $Request.body.refreshtoken -Force

                # Trigger CPV refresh for partner tenant only
                try {
                    $Queue = New-CippQueueEntry -Name 'Update Permissions - Partner Tenant' -TotalTasks 1
                    $TenantBatch = @([PSCustomObject]@{
                            defaultDomainName = 'PartnerTenant'
                            customerId        = $env:TenantID
                            displayName       = '*Partner Tenant'
                            FunctionName      = 'UpdatePermissionsQueue'
                            QueueId           = $Queue.RowKey
                        })
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'UpdatePermissionsOrchestrator'
                        Batch            = @($TenantBatch)
                    }
                    Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Information 'Started permissions update orchestrator for Partner Tenant'
                } catch {
                    Write-Warning "Failed to start permissions orchestrator: $($_.Exception.Message)"
                }
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.body.tenantId) - we're adding a new secret for the tenant."
                $name = $Request.body.tenantId
                try {
                    Set-CippKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                    # Set environment variable to make it immediately available
                    Set-Item -Path env:$name -Value $Request.body.refreshtoken -Force
                } catch {
                    Write-Host "Failed to set secret $name in KeyVault. $($_.Exception.Message)"
                    throw $_
                }
            }
        }

        if ($request.body.tenantId -eq $env:TenantID) {
            $TenantName = 'your partner tenant'
        } else {
            $TenantName = $request.body.tenantId
        }
        $Results = @{
            'resultText' = "Successfully updated the credentials for $($TenantName). You may continue to the next step, or add additional tenants if required."
            'state'      = 'success'
        }
    } catch {
        $Results = [pscustomobject]@{
            'Results' = @{
                resultText = "Failed. $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.message)"
                state      = 'failed'
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })

    }
}
