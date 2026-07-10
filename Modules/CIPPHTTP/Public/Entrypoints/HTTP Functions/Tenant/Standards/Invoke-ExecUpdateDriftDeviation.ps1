function Invoke-ExecUpdateDriftDeviation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    function Find-CIPPTagBundleEntry {
        param($Entries, $TemplateId, $TemplatePartition)

        if (-not $Entries) { return $null }

        $BundleEntry = $null
        $TemplatesTable = Get-CippTable -tablename 'templates'
        $LiveTemplate = Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$TemplatePartition' and RowKey eq '$TemplateId'"
        if (-not $LiveTemplate) {
            # Built-in templates are keyed as '<guid>.IntuneTemplate.json' / '<guid>.CATemplate.json',
            # while deviation ids may carry the bare guid - match by prefix as a fallback
            $LiveTemplate = Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$TemplatePartition'" |
                Where-Object { $_.RowKey -like "$TemplateId*" } | Select-Object -First 1
        }
        if ($LiveTemplate.Package) {
            $BundleEntry = $Entries | Where-Object {
                $TagValues = foreach ($Tag in @($_.'TemplateList-Tags')) {
                    if ($Tag.value) { $Tag.value } elseif ($Tag -is [string]) { $Tag }
                }
                @($TagValues) -contains $LiveTemplate.Package
            } | Select-Object -First 1
        }

        if (-not $BundleEntry) {
            # Fallback: the stored snapshot, for templates whose live row no longer exists
            $BundleEntry = $Entries | Where-Object {
                ($_.'TemplateList-Tags'.rawData.templates | Where-Object { $_.GUID -like "*$TemplateId*" }) -or
                ($_.'TemplateList-Tags'.addedFields.templates | Where-Object { $_.GUID -like "*$TemplateId*" })
            } | Select-Object -First 1
        }

        if ($BundleEntry) {
            $Matched = $BundleEntry.PSObject.Copy()
            $Matched.PSObject.Properties.Remove('TemplateList-Tags')
            $Matched | Add-Member -NotePropertyName TemplateList -NotePropertyValue ([pscustomobject]@{
                    label = $TemplateId
                    value = $TemplateId
                }) -Force
            return $Matched
        }
        return $null
    }

    try {
        $TenantFilter = $Request.Body.TenantFilter

        if ($Request.Body.RemoveDriftCustomization) {
            $Table = Get-CippTable -tablename 'tenantDrift'
            $Filter = "PartitionKey eq '$TenantFilter'"
            $ExistingDeviations = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            foreach ($Deviation in $ExistingDeviations) {
                Remove-AzDataTableEntity @Table -Entity $Deviation
            }
            $Results = @([PSCustomObject]@{
                    success = $true
                    result  = "All drift customizations removed for tenant $TenantFilter"
                })
            Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Removed all drift customizations for tenant $TenantFilter" -Sev 'Info'
        } else {
            $Deviations = $Request.Body.deviations
            $Reason = $Request.Body.reason
            $PersistentDeny = [bool]($Request.Body.persistentDeny)
            $Results = foreach ($Deviation in $Deviations) {
                try {
                    $user = $request.headers.'x-ms-client-principal'
                    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
                    $Result = Set-CIPPDriftDeviation -TenantFilter $TenantFilter -StandardName $Deviation.standardName -Status $Deviation.status -Reason $Reason -user $username
                    [PSCustomObject]@{
                        success = $true
                        result  = $Result
                    }
                    Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Updated drift deviation status for $($Deviation.standardName) to $($Deviation.status) with reason: $Reason" -Sev 'Info'
                    if ($Deviation.status -eq 'DeniedRemediate') {
                        $Setting = $Deviation.standardName -replace 'standards\.', ''
                        $StandardTemplate = Get-CIPPTenantAlignment -TenantFilter $TenantFilter | Where-Object -Property standardType -EQ 'drift'
                        $DriftTemplateId = $StandardTemplate.StandardId
                        $Settings = $null
                        if ($Setting -like '*IntuneTemplate*') {
                            $Setting = 'IntuneTemplate'
                            # Take everything after the prefix: template ids can contain dots
                            # (built-in templates are keyed '<guid>.IntuneTemplate.json')
                            $TemplateId = $Deviation.standardName -replace '^(standards\.)?IntuneTemplates?\.', ''
                            $MatchedTemplate = $StandardTemplate.standardSettings.IntuneTemplate | Where-Object { $_.TemplateList.value -like "*$TemplateId*" } | Select-Object -First 1
                            if (-not $MatchedTemplate) {
                                # Template may be referenced through a TemplateList-Tags bundle - resolve the
                                # tag membership live so members added after the bundle was saved still remediate
                                $MatchedTemplate = Find-CIPPTagBundleEntry -Entries $StandardTemplate.standardSettings.IntuneTemplate -TemplateId $TemplateId -TemplatePartition 'IntuneTemplate'
                            }
                            if (-not $MatchedTemplate) {
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Could not find IntuneTemplate $TemplateId in drift standard settings for remediation" -Sev 'Warning'
                            } else {
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                                $Settings = $MatchedTemplate
                            }
                        } elseif ($Setting -like '*ConditionalAccessTemplate*') {
                            $Setting = 'ConditionalAccessTemplate'
                            # Take everything after the prefix: template ids can contain dots
                            # (built-in templates are keyed '<guid>.CATemplate.json')
                            $TemplateId = $Deviation.standardName -replace '^(standards\.)?ConditionalAccessTemplates?\.', ''
                            $MatchedTemplate = $StandardTemplate.standardSettings.ConditionalAccessTemplate | Where-Object { $_.TemplateList.value -like "*$TemplateId*" } | Select-Object -First 1
                            if (-not $MatchedTemplate) {
                                # CA templates can be referenced through a TemplateList-Tags bundle too
                                $MatchedTemplate = Find-CIPPTagBundleEntry -Entries $StandardTemplate.standardSettings.ConditionalAccessTemplate -TemplateId $TemplateId -TemplatePartition 'CATemplate'
                            }
                            if (-not $MatchedTemplate) {
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Could not find ConditionalAccessTemplate $TemplateId in drift standard settings for remediation" -Sev 'Warning'
                            } else {
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                                $Settings = $MatchedTemplate
                            }
                        } else {
                            $StandardTemplate = $StandardTemplate.standardSettings.$Setting
                            # If the addedComponent values are stored nested under standards.<setting> instead of
                            # flat on the object, promote them to the top level so the standard function can read them.
                            if ($StandardTemplate.standards -and $StandardTemplate.standards.$Setting) {
                                foreach ($Prop in $StandardTemplate.standards.$Setting.PSObject.Properties) {
                                    $StandardTemplate | Add-Member -MemberType NoteProperty -Name $Prop.Name -Value $Prop.Value -Force
                                }
                                $StandardTemplate.PSObject.Properties.Remove('standards')
                            }
                            $StandardTemplate | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                            $StandardTemplate | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                            $Settings = $StandardTemplate
                        }
                        if ($Settings) {
                            $TaskBody = @{
                                TenantFilter  = $TenantFilter
                                Name          = "One Off Drift Remediation: $Setting - $TenantFilter - $DriftTemplateId"
                                Tag           = "DriftRemediation_$DriftTemplateId"
                                Command       = @{
                                    value = "Invoke-CIPPStandard$Setting"
                                    label = "Invoke-CIPPStandard$Setting"
                                }

                                Parameters    = [pscustomobject]@{
                                    Tenant   = $TenantFilter
                                    Settings = $Settings
                                }
                                ScheduledTime = '0'
                                PostExecution = @{
                                    Webhook = $false
                                    Email   = $false
                                    PSA     = $false
                                }
                            }
                            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
                            Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Scheduled drift remediation task for $Setting" -Sev 'Info'

                            if ($PersistentDeny) {
                                $PersistentTaskBody = @{
                                    TenantFilter  = $TenantFilter
                                    Name          = "Persistent Drift Remediation: $Setting - $TenantFilter - $DriftTemplateId"
                                    Tag           = "DriftRemediation_$DriftTemplateId"
                                    Command       = @{
                                        value = "Invoke-CIPPStandard$Setting"
                                        label = "Invoke-CIPPStandard$Setting"
                                    }
                                    Parameters    = [pscustomobject]@{
                                        Tenant   = $TenantFilter
                                        Settings = $Settings
                                    }
                                    ScheduledTime = '0'
                                    Recurrence    = '12h'
                                    PostExecution = @{
                                        Webhook = $false
                                        Email   = $false
                                        PSA     = $false
                                    }
                                }
                                Add-CIPPScheduledTask -Task $PersistentTaskBody -hidden $false
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Scheduled persistent drift remediation task (12h recurrence) for $Setting" -Sev 'Info'
                            }
                        } else {
                            # Surface the failure to the caller - previously this silently scheduled a
                            # remediation task with empty settings that could never do anything
                            [PSCustomObject]@{
                                standardName = $Deviation.standardName
                                success      = $false
                                error        = "The deviation status was updated, but no remediation task was scheduled: the template could not be resolved from the drift template settings. Verify the template still exists in the template library, or re-save the drift template."
                            }
                        }
                    }
                    if ($Deviation.status -eq 'deniedDelete') {
                        $Policy = $Deviation.receivedValue | ConvertFrom-Json -ErrorAction SilentlyContinue
                        Write-Host "Policy is $($Policy)"
                        if ($Deviation.standardName -like '*ConditionalAccessTemplates*') {
                            $URLName = 'identity/conditionalAccess/policies'
                        } else {
                            $URLName = Get-CIPPURLName -Template $Policy
                        }
                        $ID = $Policy.ID
                        if ($Policy -and $URLName) {
                            Write-Host "Going to delete Policy with ID $($Policy.ID) Deviation Name is $($Deviation.standardName)"
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/$($URLName)/$($ID)" -type DELETE -tenant $TenantFilter
                            "Deleted Policy $($ID)"
                            Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Deleted Policy with ID $($ID)" -Sev 'Info'
                        } else {
                            "could not find policy with ID $($ID)"
                            Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Could not find Policy with ID $($ID) to delete for remediation" -sev 'Warning'
                        }


                    }
                } catch {
                    [PSCustomObject]@{
                        standardName = $Deviation.standardName
                        success      = $false
                        error        = $_.Exception.Message
                    }
                    Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Failed to update drift deviation for $($Deviation.standardName): $($_.Exception.Message)" -Sev 'Error'
                }
            }
        }

        $Body = @{ Results = @($Results) }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })

    } catch {
        Write-LogMessage -Headers $Request.Headers -API $APINAME -message "Failed to update drift deviation: $($_.Exception.Message)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{error = $_.Exception.Message }
            })
    }
}
