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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $KV = Get-CippKeyVaultName

    $TenantId = [string]$Request.Body.tenantId
    if ($TenantId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantId must be a tenant ID (GUID).' }
            })
    }
    # A tenant CIPP does not manage yet is being onboarded, which only needs the permission.
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $TenantId) {
        $TenantsTable = Get-CIPPTable -tablename 'Tenants'
        if ($TenantId -eq $env:TenantID -or (Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and customerId eq '$TenantId'")) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = "$TenantId is outside your access." }
                })
        }
    }

    try {
        # Handle refresh token update
        #make sure we get the latest authentication:
        $auth = Get-CIPPAuthentication
        $IsPartnerTenant = $env:TenantID -eq $Request.body.tenantId
        $IsAdditionalPartner = $false

        if ($Request.body.addPartner -eq $true -and -not $IsPartnerTenant) {
            # Store as an additional partner tenant (partner-<tenantid> secret namespace).
            $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
            if (-not $Flag.Enabled) {
                throw 'The Multiple Partner Tenants feature is not enabled. Enable the MultiPartner feature flag first.'
            }
            $User = try { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json } catch { $null }
            if ($User.userRoles -notcontains 'superadmin') {
                throw 'Adding partner tenants requires the superadmin role.'
            }
            $TenantsTable = Get-CIPPTable -tablename 'Tenants'
            $ExistingDirect = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($Request.body.tenantId)' and delegatedPrivilegeStatus eq 'directTenant'"
            if ($ExistingDirect) {
                throw "Tenant $($Request.body.tenantId) is already added as a direct tenant. Remove it as a direct tenant before adding it as a partner tenant."
            }
            $IsAdditionalPartner = $true
        }

        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($IsPartnerTenant) {
                $Secret | Add-Member -MemberType NoteProperty -Name 'RefreshToken' -Value $Request.body.refreshtoken -Force
                Set-Item -Path env:RefreshToken -Value $Request.body.refreshtoken -Force
            } elseif ($IsAdditionalPartner) {
                $name = "partner-$($Request.body.tenantId)" -replace '-', '_'
                $Secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.body.refreshtoken -Force
                Set-Item -Path "env:\partner-$($Request.body.tenantId)" -Value $Request.body.refreshtoken -Force
            } else {
                $name = $Request.body.tenantId -replace '-', '_'
                $Secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.body.refreshtoken -Force
                Set-Item -Path env:$name -Value $Request.body.refreshtoken -Force
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            if ($IsPartnerTenant) {
                $null = Set-CippKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                Set-Item -Path env:RefreshToken -Value $Request.body.refreshtoken -Force
            } elseif ($IsAdditionalPartner) {
                $name = "partner-$($Request.body.tenantId)"
                $null = Set-CippKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                Set-Item -Path "env:\$name" -Value $Request.body.refreshtoken -Force
            } else {
                Write-Information "$($env:TenantID) does not match $($Request.body.tenantId) - adding a new secret for the tenant."
                $name = $Request.body.tenantId
                try {
                    $null = Set-CippKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                    Set-Item -Path env:$name -Value $Request.body.refreshtoken -Force
                } catch {
                    Write-Information "Failed to set secret $name in KeyVault. $($_.Exception.Message)"
                    throw $_
                }
            }
        }

        # Cached access tokens were minted from the old refresh token; drop them so the new one takes effect now.
        # The partner token backs every GDAP tenant, a direct tenant's token only itself (cached under GUID or domain).
        if ($IsPartnerTenant -or $IsAdditionalPartner) {
            $null = Clear-CippTokenCache
        } else {
            $null = Clear-CippTokenCache -TenantFilter $Request.body.tenantId
        }
        $null = Set-CIPPCredentialVersion

        if ($IsAdditionalPartner) {
            # Resolve org name/domain with the stored token; non-fatal on failure.
            $PartnerOrg = $null
            try {
                $PartnerOrg = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName,verifiedDomains' -tenantid $Request.body.tenantId -NoAuthCheck $true -ErrorAction Stop) | Select-Object -First 1
            } catch {
                Write-Information "Could not resolve organization info for new partner $($Request.body.tenantId): $($_.Exception.Message)"
            }
            $PartnerTable = Get-CIPPTable -tablename 'PartnerTenants'
            $PartnerEntity = @{
                PartitionKey    = 'Partners'
                RowKey          = "$($Request.body.tenantId)"
                partnerTenantId = "$($Request.body.tenantId)"
                displayName     = "$($PartnerOrg.displayName ?? $Request.body.orgName ?? $Request.body.tenantId)"
                Enabled         = $true
                addedDate       = (Get-Date).ToUniversalTime()
                lastTokenRefresh = (Get-Date).ToUniversalTime()
            }
            $PartnerDefaultDomain = ($PartnerOrg.verifiedDomains | Where-Object { $_.isDefault -eq $true }).name
            if ($PartnerDefaultDomain) {
                $PartnerEntity.defaultDomainName = "$PartnerDefaultDomain"
            }
            if ($Request.body.username) {
                $PartnerEntity.authenticatedUserPrincipalName = "$($Request.body.username)"
            }
            $null = Add-CIPPAzDataTableEntity @PartnerTable -Entity $PartnerEntity -Force
            Write-LogMessage -API 'ExecUpdateRefreshToken' -message "Added/updated partner tenant $($Request.body.tenantId)" -Sev 'Info'
        }

        if ($IsPartnerTenant -or $IsAdditionalPartner) {
            try {
                $PartnerCustomerId = if ($IsAdditionalPartner) { $Request.body.tenantId } else { $env:TenantID }
                $Queue = New-CippQueueEntry -Name 'Update Permissions - Partner Tenant' -TotalTasks 1
                $TenantBatch = @([PSCustomObject]@{
                        defaultDomainName = 'PartnerTenant'
                        customerId        = $PartnerCustomerId
                        displayName       = '*Partner Tenant'
                        FunctionName      = 'UpdatePermissionsQueue'
                        QueueId           = $Queue.RowKey
                    })
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'UpdatePermissionsOrchestrator'
                    Batch            = @($TenantBatch)
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject
                Write-Information 'Started permissions update orchestrator for Partner Tenant'
            } catch {
                Write-Warning "Failed to start permissions orchestrator: $($_.Exception.Message)"
            }
        }

        if ($request.body.tenantId -eq $env:TenantID) {
            $TenantName = 'your partner tenant'
        } elseif ($IsAdditionalPartner) {
            $TenantName = "partner tenant $($Request.body.orgName ?? $Request.body.tenantId)"
        } else {
            $TenantName = $request.body.tenantId
        }
        $Result = "Successfully updated the credentials for $($TenantName). You may continue to the next step, or add additional tenants if required."
        Write-LogMessage -headers $Headers -API $APIName -tenant $Request.body.tenantId -message $Result -Sev 'Info'
        $Results = @{
            'resultText' = $Result
            'state'      = 'success'
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update refresh token credentials. $($_.InvocationInfo.ScriptLineNumber): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Request.body.tenantId -message $Result -Sev 'Error' -LogData $ErrorMessage
        $Results = [pscustomobject]@{
            'Results' = @{
                resultText = "Failed. $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.message)"
                state      = 'failed'
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Results
            })

    }
}
