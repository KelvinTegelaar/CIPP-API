using namespace System.Net

function Invoke-ExecCombinedSetup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    #Make arraylist of Results
    $Results = [System.Collections.ArrayList]::new()
    try {
        # Set up Azure context if needed for Key Vault access
        if ($env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true' -and $env:MSI_SECRET) {
            Disable-AzContextAutosave -Scope Process | Out-Null
            $null = Connect-AzAccount -Identity
            $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            $null = Set-AzContext -SubscriptionId $SubscriptionId
        }
        if ($request.body.selectedBaselines -and $request.body.baselineOption -eq 'downloadBaselines') {
            #do a single download of the selected baselines.
            foreach ($template in $request.body.selectedBaselines) {
                $object = @{
                    TenantFilter  = 'No tenant'
                    Name          = "Download Single Baseline: $($template.value)"
                    Command       = @{
                        value = 'New-CIPPTemplateRun'
                    }
                    Parameters    = @{
                        TemplateSettings = @{
                            ca                 = $false
                            intuneconfig       = $false
                            intunecompliance   = $false
                            intuneprotection   = $false
                            templateRepo       = @{
                                label       = $Template.label
                                value       = $template.value
                                addedFields = @{
                                    branch = 'main'
                                }
                            }
                            templateRepoBranch = @{
                                label = 'main'
                                value = 'main'
                            }
                            standardsconfig    = $true
                            groupTemplates     = $true
                            policyTemplates    = $true
                            caTemplates        = $true
                        }
                    }
                    ScheduledTime = 0
                }
                $null = Add-CIPPScheduledTask -task $object -hidden $false -DisallowDuplicateName $true -Headers $Request.Headers
                $Results.add("Scheduled download of baseline: $($template.value)")
            }
        }
        if ($Request.body.email -or $Request.body.webhook) {
            #create hashtable from pscustomobject
            $notificationConfig = $request.body | Select-Object email, webhook, onepertenant, logsToInclude, sendtoIntegration, sev | ConvertTo-Json | ConvertFrom-Json -AsHashtable
            $notificationResults = Set-CIPPNotificationConfig @notificationConfig
            $Results.add($notificationResults)
        }
        if ($Request.Body.selectedOption -eq 'Manual') {
            $KV = $env:WEBSITE_DEPLOYMENT_ID

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                if (!$Secret) {
                    $Secret = [PSCustomObject]@{
                        'PartitionKey'      = 'Secret'
                        'RowKey'            = 'Secret'
                        'TenantId'          = ''
                        'RefreshToken'      = ''
                        'ApplicationId'     = ''
                        'ApplicationSecret' = ''
                    }
                    Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                }

                if ($Request.Body.tenantId) { $Secret.TenantId = $Request.Body.tenantid }
                if ($Request.Body.applicationId) { $Secret.ApplicationId = $Request.Body.applicationId }
                if ($Request.Body.ApplicationSecret) { $Secret.ApplicationSecret = $Request.Body.ApplicationSecret }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                $Results.add('Manual credentials have been set in the DevSecrets table.')
            } else {
                if ($Request.Body.tenantId) {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'tenantid' -SecretValue (ConvertTo-SecureString -String $Request.Body.tenantId -AsPlainText -Force)
                    $Results.add('Set tenant ID in Key Vault.')
                }
                if ($Request.Body.applicationId) {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationid' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationId -AsPlainText -Force)
                    $Results.add('Set application ID in Key Vault.')
                }
                if ($Request.Body.applicationSecret) {
                    Set-AzKeyVaultSecret -VaultName $kv -Name 'applicationsecret' -SecretValue (ConvertTo-SecureString -String $Request.Body.applicationSecret -AsPlainText -Force)
                    $Results.add('Set application secret in Key Vault.')
                }
            }

            $Results.add('Manual credentials setup has been completed.')
        }

        $Results.add('Setup is now complete. You may navigate away from this page and start using CIPP.')
        #one more force of reauth so env vars update.
        $auth = Get-CIPPAuthentication
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $($_.Exception.message)"; severity = 'failed' }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
