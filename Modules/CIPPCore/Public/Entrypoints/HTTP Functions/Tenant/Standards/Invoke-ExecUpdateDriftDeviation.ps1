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
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

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
            Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Removed all drift customizations for tenant $TenantFilter" -Sev 'Info'
        } else {
            $Deviations = $Request.Body.deviations
            $Reason = $Request.Body.reason
            $Results = foreach ($Deviation in $Deviations) {
                try {
                    $user = $request.headers.'x-ms-client-principal'
                    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
                    $Result = Set-CIPPDriftDeviation -TenantFilter $TenantFilter -StandardName $Deviation.standardName -Status $Deviation.status -Reason $Reason -user $username
                    [PSCustomObject]@{
                        success = $true
                        result  = $Result
                    }
                    Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Updated drift deviation status for $($Deviation.standardName) to $($Deviation.status) with reason: $Reason" -Sev 'Info'
                    if ($Deviation.status -eq 'DeniedRemediate') {
                        $Setting = $Deviation.standardName -replace 'standards.', ''
                        $StandardTemplate = Get-CIPPTenantAlignment -TenantFilter $TenantFilter | Where-Object -Property standardType -EQ 'drift'
                        if ($Setting -like '*IntuneTemplate*') {
                            $Setting = 'IntuneTemplate'
                            $TemplateId = $Deviation.standardName.split('.') | Select-Object -Last 1
                            $StandardTemplate = $StandardTemplate.standardSettings.IntuneTemplate | Where-Object { $_.TemplateList.value -eq $TemplateId }
                            $StandardTemplate | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                            $StandardTemplate | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                            $Settings = $StandardTemplate
                        } else {
                            $StandardTemplate = $StandardTemplate.standardSettings.$Setting
                            $StandardTemplate.standards.$Setting | Add-Member -MemberType NoteProperty -Name 'remediate' -Value $true -Force
                            $StandardTemplate.standards.$Setting | Add-Member -MemberType NoteProperty -Name 'report' -Value $true -Force
                            $Settings = $StandardTemplate.standards.$Setting
                        }
                        $TaskBody = @{
                            TenantFilter  = $TenantFilter
                            Name          = "One Off Drift Remediation: $Setting - $TenantFilter"
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
                        Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Scheduled drift remediation task for $Setting" -Sev 'Info'
                    }
                    if ($Deviation.status -eq 'deniedDelete') {
                        $Policy = $Deviation.receivedValue | ConvertFrom-Json -ErrorAction SilentlyContinue
                        Write-Host "Policy is $($Policy)"
                        $URLName = Get-CIPPURLName -Template $Policy
                        if ($Policy -and $URLName) {
                            Write-Host "Going to delete Policy with ID $($policy.ID) Deviation Name is $($Deviation.standardName)"
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/$($URLName)/$($policy.id)" -type DELETE -tenant $TenantFilter
                            "Deleted Policy $($ID)"
                            Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Deleted Policy with ID $($ID)" -Sev 'Info'
                        } else {
                            "could not find policy with ID $($ID)"
                            Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not find Policy with ID $($ID) to delete for remediation" -Sev 'Warning'
                        }


                    }
                } catch {
                    [PSCustomObject]@{
                        standardName = $Deviation.standardName
                        success      = $false
                        error        = $_.Exception.Message
                    }
                    Write-LogMessage -tenant $TenantFilter -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to update drift deviation for $($Deviation.standardName): $($_.Exception.Message)" -Sev 'Error'
                }
            }
        }

        $Body = @{ Results = @($Results) }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })

    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to update drift deviation: $($_.Exception.Message)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{error = $_.Exception.Message }
            })
    }
}
