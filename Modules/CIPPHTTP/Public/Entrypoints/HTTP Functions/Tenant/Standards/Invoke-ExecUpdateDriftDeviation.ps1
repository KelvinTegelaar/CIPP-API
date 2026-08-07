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
                Remove-CIPPAzDataTableEntity @Table -Entity $Deviation
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
            # Intune multi-admin approval rejects any write that carries no justification header
            # ("Header 'x-msft-approval-justification' is required to request approval"). The header is
            # ignored on tenants and resources that do not require approval, so send it on every delete.
            # The value must be base64 of the UTF-8 text - Intune rejects plain text outright.
            $Justification = [string]$Reason
            if ([string]::IsNullOrWhiteSpace($Justification)) { $Justification = 'Denied and deleted from CIPP drift review' }
            if ($Justification.Length -gt 1024) { $Justification = $Justification.Substring(0, 1024) }
            $Justification = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Justification))
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
                        } elseif ($Setting -like '*QuarantineTemplate*') {
                            $Setting = 'QuarantineTemplate'
                            # The suffix is the quarantine policy display name, hex encoded because '\', '#'
                            # and '?' are legal in a quarantine name but not in an Azure Table RowKey.
                            # See the matching encoder in Invoke-CIPPStandardQuarantineTemplate.
                            $HexName = $Deviation.standardName -replace '^(standards\.)?QuarantineTemplates?\.', ''
                            $PolicyName = $null
                            if ($HexName -match '^[0-9A-Fa-f]+$' -and $HexName.Length % 2 -eq 0) {
                                $Chars = for ($i = 0; $i -lt $HexName.Length; $i += 2) {
                                    [char][Convert]::ToInt32($HexName.Substring($i, 2), 16)
                                }
                                $PolicyName = -join $Chars
                            }
                            $MatchedTemplate = $StandardTemplate.standardSettings.QuarantineTemplate | Where-Object {
                                ($_.displayName.value ?? [string]$_.displayName) -eq $PolicyName
                            } | Select-Object -First 1
                            if (-not $MatchedTemplate) {
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Could not find QuarantineTemplate '$PolicyName' in drift standard settings for remediation" -Sev 'Warning'
                            } else {
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                                $MatchedTemplate | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                                $Settings = $MatchedTemplate
                            }
                        } elseif ($Setting -like '*ReusableSettingsTemplate*') {
                            $Setting = 'ReusableSettingsTemplate'
                            $TemplateId = $Deviation.standardName -replace '^(standards\.)?ReusableSettingsTemplates?\.', ''
                            $MatchedTemplate = $StandardTemplate.standardSettings.ReusableSettingsTemplate | Where-Object { $_.TemplateList.value -like "*$TemplateId*" } | Select-Object -First 1
                            if (-not $MatchedTemplate) {
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Could not find ReusableSettingsTemplate $TemplateId in drift standard settings for remediation" -Sev 'Warning'
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
                                error        = "The deviation status was updated, but no remediation task was scheduled: '$Setting' could not be resolved from the drift template settings. Verify the template still exists in the template library and is included in the drift template, or re-save the drift template."
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
                            try {
                                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/$($URLName)/$($ID)" -type DELETE -tenantid $TenantFilter -AddedHeaders @{ 'x-msft-approval-justification' = $Justification }
                                "Deleted Policy $($ID)"
                                Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Deleted Policy with ID $($ID)" -Sev 'Info'
                            } catch {
                                # Multi-admin approval never deletes inline. The first call registers an approval
                                # request, fails, and returns its id in the x-msft-approval-code header (echoed
                                # into the error body); repeat calls while that request is open fail with "An
                                # active Approval Request already exists" and no header. Both are pending changes
                                # rather than failures - report them so the deletion can be tracked in Intune.
                                $RawError = $_.Exception.Data['RawErrorBody'] ?? $_.Exception.Message
                                $ApprovalCode = if ($RawError -match 'x-msft-approval-code["'':\\\s]*([0-9a-fA-F-]{36})') { $Matches[1] } else { $null }
                                $ApprovalExists = $RawError -match 'active Approval Request already exists'
                                if ($ApprovalCode) {
                                    # Approval alone does not perform the delete - the request has to be
                                    # resubmitted with the approval code once a second admin approves it.
                                    # Hand that off so the deletion completes without anyone returning here.
                                    try {
                                        $null = Invoke-CIPPIntuneApprovalRetry -TenantFilter $TenantFilter -ApprovalCode $ApprovalCode -ResourcePath "$($URLName)/$($ID)" -Type 'DELETE'
                                        $ApprovalText = "Approval request $ApprovalCode has been raised - CIPP will complete the deletion once another administrator approves it in Intune"
                                    } catch {
                                        $ApprovalText = "Approval request $ApprovalCode has been raised, but the follow-up could not be scheduled ($($_.Exception.Message)). Approve the request in Intune and repeat this action"
                                    }
                                    [PSCustomObject]@{
                                        resultText = "Policy $($ID) was not deleted: this tenant requires multi-admin approval in Intune. $ApprovalText."
                                        state      = 'warning'
                                        copyField  = $ApprovalCode
                                    }
                                    Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Deletion of policy $($ID) requires multi-admin approval. $ApprovalText." -Sev 'Warning'
                                } elseif ($ApprovalExists) {
                                    # A request raised earlier is still open, and Intune returns no code for it,
                                    # so there is nothing to poll against - the admin has to drive this one.
                                    [PSCustomObject]@{
                                        resultText = "Policy $($ID) was not deleted: an Intune multi-admin approval request for it is already open. Approve or reject it in Intune, then repeat this action."
                                        state      = 'warning'
                                    }
                                    Write-LogMessage -tenant $TenantFilter -Headers $Request.Headers -API $APINAME -message "Deletion of policy $($ID) is already awaiting multi-admin approval in Intune." -Sev 'Warning'
                                } else {
                                    throw
                                }
                            }
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
