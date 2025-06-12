using namespace System.Net

Function Invoke-ExecCombinedSetup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    #Make arraylist of Results
    $Results = [System.Collections.ArrayList]::new()
    try {
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
